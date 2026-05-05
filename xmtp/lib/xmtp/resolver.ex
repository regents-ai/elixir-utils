defmodule Xmtp.Resolver do
  @moduledoc """
  Shared wallet and inbox resolver with bounded caching.
  """

  use GenServer

  alias Xmtp.Identity
  alias Xmtp.Principal
  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Runtime
  alias XmtpElixirSdk.Types

  @positive_ttl_ms :timer.minutes(5)
  @null_ttl_ms :timer.seconds(30)

  defstruct cache: %{}, positive_ttl_ms: @positive_ttl_ms, null_ttl_ms: @null_ttl_ms

  @type target ::
          %{required(:wallet_address) => String.t()} | %{required(:inbox_id) => String.t()}

  @type result :: %{
          required(:status) => :ready | :not_found | :cannot_message,
          required(:wallet_address) => String.t() | nil,
          required(:inbox_id) => String.t() | nil,
          required(:can_message?) => boolean()
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    %{id: name, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       positive_ttl_ms: Keyword.get(opts, :positive_ttl_ms, @positive_ttl_ms),
       null_ttl_ms: Keyword.get(opts, :null_ttl_ms, @null_ttl_ms)
     }}
  end

  @spec resolve_wallet(GenServer.server(), Client.t() | Runtime.t() | atom(), String.t()) ::
          {:ok, result()} | {:error, term()}
  def resolve_wallet(server \\ __MODULE__, runtime_or_client, wallet_address) do
    GenServer.call(server, {:resolve_wallet, runtime_or_client, wallet_address})
  end

  @spec can_message?(GenServer.server(), Client.t() | Runtime.t() | atom(), String.t()) ::
          {:ok, boolean()} | {:error, term()}
  def can_message?(server \\ __MODULE__, runtime_or_client, wallet_address) do
    with {:ok, result} <- resolve_wallet(server, runtime_or_client, wallet_address) do
      {:ok, result.can_message?}
    end
  end

  @spec resolve_for_room_invite(GenServer.server(), Client.t() | Runtime.t() | atom(), target()) ::
          {:ok, result()} | {:error, term()}
  def resolve_for_room_invite(server \\ __MODULE__, runtime_or_client, target) do
    case target do
      %{wallet_address: wallet_address} ->
        resolve_wallet(server, runtime_or_client, wallet_address)

      %{inbox_id: inbox_id} ->
        {:ok, inbox_result(inbox_id)}

      %Principal{} = principal ->
        resolve_wallet(server, runtime_or_client, Principal.wallet(principal))

      _target ->
        {:error, :invalid_resolver_target}
    end
  end

  @spec find_or_create_dm_target(GenServer.server(), Client.t() | Runtime.t() | atom(), target()) ::
          {:ok, result()} | {:error, term()}
  def find_or_create_dm_target(server \\ __MODULE__, runtime_or_client, target) do
    resolve_for_room_invite(server, runtime_or_client, target)
  end

  @impl true
  def handle_call({:resolve_wallet, runtime_or_client, wallet_address}, _from, state) do
    with {:ok, wallet_address} <- normalize_wallet(wallet_address) do
      key = {runtime_key(runtime_or_client), :wallet, wallet_address}

      case cached(state, key) do
        {:hit, result} ->
          {:reply, {:ok, result}, state}

        :miss ->
          {reply, next_state} = resolve_uncached(runtime_or_client, wallet_address, key, state)
          {:reply, reply, next_state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp resolve_uncached(runtime_or_client, wallet_address, key, state) do
    identifier = Identity.wallet_identifier(wallet_address)

    with {:ok, can_message_result} <- Clients.can_message(runtime_or_client, [identifier]),
         can_message? = Map.get(can_message_result, identifier_key(identifier), false),
         {:ok, inbox_id} <- Clients.fetch_inbox_id_by_identifier(runtime_or_client, identifier) do
      result =
        cond do
          is_nil(inbox_id) ->
            %{
              status: :not_found,
              wallet_address: wallet_address,
              inbox_id: nil,
              can_message?: false
            }

          can_message? ->
            %{
              status: :ready,
              wallet_address: wallet_address,
              inbox_id: inbox_id,
              can_message?: true
            }

          true ->
            %{
              status: :cannot_message,
              wallet_address: wallet_address,
              inbox_id: inbox_id,
              can_message?: false
            }
        end

      {{:ok, result}, put_cache(state, key, result)}
    end
  end

  defp cached(state, key) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state.cache, key) do
      %{expires_at: expires_at, result: result} when expires_at > now -> {:hit, result}
      _entry -> :miss
    end
  end

  defp put_cache(state, key, result) do
    ttl =
      case result.status do
        :ready -> state.positive_ttl_ms
        _status -> state.null_ttl_ms
      end

    expires_at = System.monotonic_time(:millisecond) + ttl
    %{state | cache: Map.put(state.cache, key, %{expires_at: expires_at, result: result})}
  end

  defp normalize_wallet(wallet_address) when is_binary(wallet_address) do
    wallet_address
    |> Principal.normalize_wallet()
    |> case do
      nil -> {:error, :wallet_required}
      wallet -> {:ok, wallet}
    end
  end

  defp normalize_wallet(_wallet_address), do: {:error, :wallet_required}

  defp inbox_result(inbox_id) when is_binary(inbox_id) do
    %{status: :ready, wallet_address: nil, inbox_id: inbox_id, can_message?: true}
  end

  defp runtime_key(%Client{runtime: runtime}), do: runtime
  defp runtime_key(%Runtime{name: name}), do: name
  defp runtime_key(runtime) when is_atom(runtime), do: runtime

  defp identifier_key(%Types.Identifier{} = identifier) do
    "#{identifier.identifier_kind}:#{identifier.identifier}"
  end
end
