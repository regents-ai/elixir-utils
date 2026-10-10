defmodule RegentPoints.NftsTest do
  use ExUnit.Case, async: false

  defmodule Chain do
    def rpc(_chain, "eth_getBlockByNumber", [tag, false]) do
      number =
        if tag == "finalized",
          do: head(),
          else: String.to_integer(String.trim_leading(tag, "0x"), 16)

      timestamp = if number == 0, do: 0, else: DateTime.to_unix(stop()) - 200 + 2 * number

      {:ok,
       %{
         "number" => hex(number),
         "hash" => hash(number),
         "parentHash" => hash(max(number - 1, 0)),
         "timestamp" => hex(timestamp)
       }}
    end

    defp stop, do: Application.fetch_env!(:regent_points, :test_stop)
    defp head, do: Application.fetch_env!(:regent_points, :test_head)
    defp hex(n), do: "0x" <> Integer.to_string(n, 16)
    defp hash(n), do: "0x" <> String.pad_leading(Integer.to_string(n, 16), 64, "0")
  end

  setup do
    original = Application.get_all_env(:regent_points)

    on_exit(fn ->
      for key <- [:chain_client, :test_stop, :test_head] do
        if Keyword.has_key?(original, key),
          do: Application.put_env(:regent_points, key, original[key]),
          else: Application.delete_env(:regent_points, key)
      end
    end)

    Application.put_env(:regent_points, :chain_client, Chain)
    Application.put_env(:regent_points, :test_stop, ~U[2026-11-09 12:00:00Z])
    Application.put_env(:regent_points, :test_head, 101)
    :ok
  end

  test "a block exactly at the cutoff belongs to the following period" do
    assert {:ok, %{number: 99}} = RegentPoints.Nfts.period_end_block(~U[2026-11-09 12:00:00Z])
  end

  test "a fractional cutoff preserves the full timestamp when selecting its block" do
    assert {:ok, %{number: 100}} =
             RegentPoints.Nfts.period_end_block(~U[2026-11-09 12:00:00.000001Z])
  end

  test "a finalized head before period end cannot select a snapshot" do
    Application.put_env(:regent_points, :test_head, 99)

    assert {:error, :snapshot_block_not_finalized} =
             RegentPoints.Nfts.period_end_block(~U[2026-11-09 12:00:00Z])
  end
end
