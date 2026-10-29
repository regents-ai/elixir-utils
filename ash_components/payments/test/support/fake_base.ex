defmodule RegentPayments.Test.FakeBase do
  @moduledoc """
  A fake Base for transactions signed with a site's own key: it answers the
  calls a send makes, keeps every raw transaction it receives in order, and
  answers each receipt with what `receipts` says of that hash (`"0x1"`,
  `"0x0"`, or nil for not yet). The wallet's count at `"pending"` is every
  transaction received; at `"latest"`, only those with a receipt. Started
  from a test, under its supervisor.
  """

  import Plug.Conn

  alias Ethers.Transaction

  @doc "Starts the fake chain; returns what it received and a signer pointed at it."
  def start(receipts: receipts) do
    seen = ExUnit.Callbacks.start_supervised!({Agent, fn -> [] end}, id: make_ref())

    server =
      ExUnit.Callbacks.start_supervised!(
        Supervisor.child_spec(
          {Bandit,
           plug: fn conn, _ ->
             {:ok, body, conn} = read_body(conn)
             answer = body |> JSON.decode!() |> rpc(seen, receipts)

             conn
             |> put_resp_content_type("application/json")
             |> send_resp(200, JSON.encode!(answer))
           end,
           ip: {127, 0, 0, 1},
           port: 0},
          id: make_ref()
        )
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    key = :crypto.strong_rand_bytes(32)
    {:ok, address} = X402.EIP3009.derive_address(key)

    signer = %{
      address: address,
      private_key: Base.encode16(key, case: :lower),
      rpc_url: "http://127.0.0.1:#{port}"
    }

    {seen, signer}
  end

  @doc "The hash the fake chain gives the `n`th transaction it receives."
  def hash(n), do: "0x" <> String.pad_leading(Integer.to_string(n, 16), 64, "0")

  @doc "The transactions the fake chain received, decoded, in the order sent."
  def sent(seen) do
    seen
    |> Agent.get(& &1)
    |> Enum.map(fn raw ->
      {:ok, %Transaction.Signed{payload: payload}} = Transaction.decode(raw)
      %{payload | to: String.downcase(payload.to)}
    end)
  end

  defp rpc(requests, seen, receipts) when is_list(requests),
    do: Enum.map(requests, &rpc(&1, seen, receipts))

  defp rpc(%{"id" => id, "method" => method} = request, seen, receipts) do
    result =
      case method do
        "eth_chainId" ->
          "0x7a69"

        "eth_getTransactionCount" ->
          [_address, block] = request["params"]
          "0x" <> Integer.to_string(count(seen, receipts, block), 16)

        "eth_estimateGas" ->
          "0x186a0"

        "eth_gasPrice" ->
          "0x3b9aca00"

        "eth_maxPriorityFeePerGas" ->
          "0x1"

        "eth_feeHistory" ->
          %{
            oldestBlock: "0x0",
            baseFeePerGas: ["0x1", "0x1"],
            gasUsedRatio: [0.5],
            reward: [["0x1"]]
          }

        "eth_sendRawTransaction" ->
          [raw] = request["params"]
          Agent.update(seen, &(&1 ++ [raw]))
          hash(length(Agent.get(seen, & &1)))

        "eth_getTransactionReceipt" ->
          [hash] = request["params"]
          %{"transactionHash" => hash, "status" => receipts.(hash)}
      end

    %{jsonrpc: "2.0", id: id, result: result}
  end

  defp count(seen, _receipts, "pending"), do: length(Agent.get(seen, & &1))

  defp count(seen, receipts, "latest") do
    seen
    |> Agent.get(&length/1)
    |> then(&Enum.take_while(1..&1//1, fn n -> receipts.(hash(n)) end))
    |> length()
  end
end
