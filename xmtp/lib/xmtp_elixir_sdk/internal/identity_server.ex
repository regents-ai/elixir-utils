defmodule XmtpElixirSdk.Internal.IdentityServer do
  @moduledoc false

  use GenServer

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Internal.StatsServer
  alias XmtpElixirSdk.Signer
  alias XmtpElixirSdk.Types
  alias XmtpElixirSdk.Types.{Identifier, InboxState, Installation}

  @type state :: %{
          clients: %{optional(String.t()) => map()},
          clients_by_identifier: %{optional(String.t()) => String.t()},
          inbox_consent: %{optional(String.t()) => Types.consent_state()},
          signature_requests: %{optional(String.t()) => map()},
          next_client_id: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    runtime = Keyword.fetch!(opts, :runtime)
    GenServer.start_link(__MODULE__, %{runtime: runtime}, name: name)
  end

  @spec reset!(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) :: :ok
  def reset!(runtime), do: GenServer.call(Names.identity_server(runtime), :reset)

  @spec create_client(XmtpElixirSdk.Runtime.t() | atom(), Identifier.t(), keyword(), boolean()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_client(runtime, identifier, opts, register?) do
    GenServer.call(Names.identity_server(runtime), {:create_client, identifier, opts, register?})
  end

  @spec close_client(XmtpElixirSdk.Client.t()) :: :ok
  def close_client(%{runtime: runtime, id: client_id}) do
    GenServer.call(Names.identity_server(runtime), {:close_client, client_id})
  end

  @spec register_client(XmtpElixirSdk.Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def register_client(%{runtime: runtime, id: client_id}) do
    GenServer.call(Names.identity_server(runtime), {:register_client, client_id})
  end

  @spec client_state(XmtpElixirSdk.Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def client_state(%{runtime: runtime, id: client_id}) do
    GenServer.call(Names.identity_server(runtime), {:client_state, client_id})
  end

  @spec fetch_client(XmtpElixirSdk.Client.t() | XmtpElixirSdk.Runtime.t() | atom(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def fetch_client(runtime, client_id) do
    GenServer.call(Names.identity_server(runtime), {:fetch_client, client_id})
  end

  @spec get_inbox_id_for_identifier(XmtpElixirSdk.Runtime.t() | atom(), Identifier.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def get_inbox_id_for_identifier(runtime, identifier) do
    GenServer.call(Names.identity_server(runtime), {:get_inbox_id_for_identifier, identifier})
  end

  @spec can_message(XmtpElixirSdk.Runtime.t() | atom(), [Identifier.t()]) ::
          {:ok, map()} | {:error, Error.t()}
  def can_message(runtime, identifiers) do
    GenServer.call(Names.identity_server(runtime), {:can_message, identifiers})
  end

  @spec inbox_state(XmtpElixirSdk.Client.t(), boolean()) ::
          {:ok, InboxState.t()} | {:error, Error.t()}
  def inbox_state(client, refresh \\ false) do
    GenServer.call(Names.identity_server(client), {:inbox_state, client.id, refresh})
  end

  @spec inbox_state_from_inbox_ids(XmtpElixirSdk.Client.t(), [String.t()], boolean()) ::
          {:ok, [InboxState.t()]} | {:error, Error.t()}
  def inbox_state_from_inbox_ids(client, inbox_ids, refresh \\ false) do
    GenServer.call(
      Names.identity_server(client),
      {:inbox_state_from_inbox_ids, client.id, inbox_ids, refresh}
    )
  end

  @spec fetch_inbox_states(XmtpElixirSdk.Runtime.t() | atom(), [String.t()], boolean()) ::
          {:ok, [InboxState.t()]} | {:error, Error.t()}
  def fetch_inbox_states(runtime, inbox_ids, refresh \\ true) do
    GenServer.call(Names.identity_server(runtime), {:fetch_inbox_states, inbox_ids, refresh})
  end

  @spec apply_consent_records(XmtpElixirSdk.Client.t(), [Types.consent_record()]) ::
          {:ok, :ok} | {:error, Error.t()}
  def apply_consent_records(client, records) do
    GenServer.call(Names.identity_server(client), {:apply_consent_records, client.id, records})
  end

  @spec consent_for_inbox(XmtpElixirSdk.Client.t(), String.t()) :: {:ok, Types.consent_state()}
  def consent_for_inbox(client, inbox_id) do
    GenServer.call(Names.identity_server(client), {:consent_for_inbox, inbox_id})
  end

  @spec create_signature_request(XmtpElixirSdk.Client.t(), atom(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_signature_request(client, action, data) do
    GenServer.call(
      Names.identity_server(client),
      {:create_signature_request, client.id, action, data}
    )
  end

  @spec apply_signature_request(XmtpElixirSdk.Client.t(), String.t(), map()) ::
          :ok | {:error, Error.t()}
  def apply_signature_request(client, signature_request_id, signer) do
    GenServer.call(
      Names.identity_server(client),
      {:apply_signature_request, client.id, signature_request_id, signer}
    )
  end

  @impl true
  def init(%{runtime: runtime}) do
    {:ok,
     %{
       runtime: runtime,
       clients: %{},
       clients_by_identifier: %{},
       inbox_consent: %{},
       signature_requests: %{},
       next_client_id: 1
     }}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok,
     %{
       runtime: state.runtime,
       clients: %{},
       clients_by_identifier: %{},
       inbox_consent: %{},
       signature_requests: %{},
       next_client_id: 1
     }}
  end

  def handle_call({:create_client, identifier, opts, register?}, _from, state) do
    client_id = "client-" <> Integer.to_string(state.next_client_id)

    inbox_id =
      generate_inbox_id(identifier, Keyword.get(opts, :kind, 0), Keyword.get(opts, :nonce, 1))

    installation_id = "installation-#{state.next_client_id}"

    client = %{
      id: client_id,
      identifier: identifier,
      inbox_id: inbox_id,
      installation_id: installation_id,
      installation_id_bytes: :crypto.hash(:sha256, installation_id),
      env: Keyword.get(opts, :env, :dev),
      app_version: Keyword.get(opts, :app_version, "0.1.0"),
      libxmtp_version: "elixir-core",
      registered?: register?,
      account_identifiers: [identifier],
      recovery_identifier: identifier,
      options: opts
    }

    next_state = %{
      state
      | clients: Map.put(state.clients, client_id, client),
        clients_by_identifier:
          Map.put(state.clients_by_identifier, identifier_key(identifier), inbox_id),
        next_client_id: state.next_client_id + 1
    }

    {:reply, {:ok, client}, next_state}
  end

  def handle_call({:close_client, client_id}, _from, state) do
    client = Map.get(state.clients, client_id)

    next_state =
      case client do
        nil ->
          state

        %{identifier: identifier} ->
          key = identifier_key(identifier)

          remaining_clients =
            state.clients
            |> Map.delete(client_id)
            |> Map.values()

          remaining_inbox_id =
            Enum.find_value(remaining_clients, fn other ->
              if identifier_key(other.identifier) == key, do: other.inbox_id, else: nil
            end)

          %{
            state
            | clients: Map.delete(state.clients, client_id),
              clients_by_identifier:
                if(is_nil(remaining_inbox_id),
                  do: Map.delete(state.clients_by_identifier, key),
                  else: Map.put(state.clients_by_identifier, key, remaining_inbox_id)
                )
          }
      end

    {:reply, :ok, next_state}
  end

  def handle_call({:register_client, client_id}, _from, state) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        updated = %{client | registered?: true}
        {:reply, {:ok, updated}, put_in(state.clients[client_id], updated)}

      :error ->
        {:reply, {:error, Error.not_found("client not found", %{client_id: client_id})}, state}
    end
  end

  def handle_call({:client_state, client_id}, _from, state) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        {:reply, {:ok, client}, state}

      :error ->
        {:reply, {:error, Error.not_found("client not found", %{client_id: client_id})}, state}
    end
  end

  def handle_call({:fetch_client, client_id}, _from, state) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        {:reply, {:ok, client}, state}

      :error ->
        {:reply, {:error, Error.not_found("client not found", %{client_id: client_id})}, state}
    end
  end

  def handle_call({:get_inbox_id_for_identifier, identifier}, _from, state) do
    case Map.get(state.clients_by_identifier, identifier_key(identifier)) do
      nil ->
        {:reply,
         {:error, Error.not_found("identifier not registered", %{identifier: identifier})}, state}

      inbox_id ->
        {:reply, {:ok, inbox_id}, state}
    end
  end

  def handle_call({:can_message, identifiers}, _from, state) do
    result =
      identifiers
      |> Enum.map(fn identifier ->
        {identifier_key(identifier),
         Map.has_key?(state.clients_by_identifier, identifier_key(identifier))}
      end)
      |> Map.new()

    {:reply, {:ok, result}, state}
  end

  def handle_call({:inbox_state, client_id, _refresh}, _from, state) do
    with {:ok, client} <- fetch_client_from_state(state, client_id) do
      {:reply, {:ok, build_inbox_state(client, state)}, state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:inbox_state_from_inbox_ids, _client_id, inbox_ids, _refresh}, _from, state) do
    {:reply, {:ok, fetch_inbox_states_by_ids(state, inbox_ids)}, state}
  end

  def handle_call({:fetch_inbox_states, inbox_ids, _refresh}, _from, state) do
    {:reply, {:ok, fetch_inbox_states_by_ids(state, inbox_ids)}, state}
  end

  def handle_call({:apply_consent_records, client_id, records}, _from, state) do
    with {:ok, normalized_records} <- normalize_consent_records(records) do
      next_state =
        Enum.reduce(normalized_records, state, fn record, acc ->
          case Map.get(record, :entity) do
            nil -> acc
            inbox_id -> put_in(acc.inbox_consent[inbox_id], Map.get(record, :state, :unknown))
          end
        end)

      StatsServer.bump_identity(state.runtime, :publish_identity_update)

      Events.emit(state.runtime, {:consent, client_id}, %Events.ConsentUpdated{
        records: normalized_records
      })

      Events.emit(
        state.runtime,
        {:preferences, client_id},
        %Events.PreferenceUpdated{
          updates: Enum.map(normalized_records, &preference_update_from_consent_record/1)
        }
      )

      {:reply, {:ok, :ok}, next_state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:consent_for_inbox, inbox_id}, _from, state) do
    {:reply, {:ok, Map.get(state.inbox_consent, inbox_id, :unknown)}, state}
  end

  def handle_call({:create_signature_request, client_id, action, data}, _from, state) do
    with {:ok, client} <- fetch_client_from_state(state, client_id) do
      request_id = "sigreq-#{map_size(state.signature_requests) + 1}"
      signature_text = "#{inspect(action)}:#{client.inbox_id}:#{request_id}:#{inspect(data)}"

      request = %{
        id: request_id,
        action: action,
        client_id: client_id,
        data: data,
        signature_text: signature_text,
        applied?: false
      }

      Events.emit(state.runtime, {:preferences, client_id}, %Events.SignatureRequestCreated{
        client_id: client_id,
        action: action,
        signature_request_id: request_id,
        signature_text: signature_text
      })

      {:reply, {:ok, %{signature_text: signature_text, signature_request_id: request_id}},
       %{state | signature_requests: Map.put(state.signature_requests, request_id, request)}}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {:apply_signature_request, client_id, signature_request_id, signer},
        _from,
        state
      ) do
    case Map.fetch(state.signature_requests, signature_request_id) do
      :error ->
        {:reply,
         {:error,
          Error.not_found("signature request not found", %{
            signature_request_id: signature_request_id
          })}, state}

      {:ok, request} ->
        with :ok <- ensure_signature_request_client(request, client_id, signature_request_id),
             :ok <- verify_signature_request_signer(state, request, signer) do
          next_state = apply_signature_request_action(state, request, signer)
          applied_request = %{request | applied?: true}

          {:reply, :ok,
           %{
             next_state
             | signature_requests:
                 Map.put(next_state.signature_requests, signature_request_id, applied_request)
           }}
        else
          {:error, error} -> {:reply, {:error, error}, state}
        end
    end
  end

  defp fetch_client_from_state(state, client_id) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, Error.not_found("client not found", %{client_id: client_id})}
    end
  end

  defp ensure_signature_request_client(request, client_id, signature_request_id) do
    if request.client_id == client_id do
      :ok
    else
      {:error,
       Error.conflict("signature request belongs to another client", %{
         signature_request_id: signature_request_id
       })}
    end
  end

  defp verify_signature_request_signer(state, request, signer) do
    with {:ok, client} <- fetch_client_from_state(state, request.client_id),
         {:ok, expected_identifier} <- expected_signature_identifier(request, client),
         :ok <- ensure_signer_identifier(signer, expected_identifier),
         :ok <- Signer.verify(signer, request.signature_text) do
      :ok
    end
  end

  defp expected_signature_identifier(
         %{action: :add_account, data: %{identifier: identifier}},
         _client
       ),
       do: {:ok, identifier}

  defp expected_signature_identifier(
         %{action: :remove_account, data: %{identifier: identifier}},
         _client
       ),
       do: {:ok, identifier}

  defp expected_signature_identifier(_request, client), do: {:ok, client.identifier}

  defp ensure_signer_identifier(%{identifier: identifier}, expected_identifier) do
    if identifier_key(identifier) == identifier_key(expected_identifier) do
      :ok
    else
      {:error, Error.invalid_argument("signature signer does not match request", %{})}
    end
  end

  defp ensure_signer_identifier(_signer, _expected_identifier),
    do: {:error, Error.invalid_argument("invalid signer payload", %{})}

  defp identifier_key(%Identifier{identifier: identifier, identifier_kind: kind}),
    do: "#{kind}:#{identifier}"

  defp identifier_key(%{identifier: identifier, identifier_kind: kind}),
    do: "#{kind}:#{identifier}"

  defp identifier_key(other), do: inspect(other)

  defp preference_update_from_consent_record(record) do
    %Types.PreferenceUpdate{
      kind: :consent,
      consent: %Types.ConsentUpdate{
        entity_type: consent_entity_type(record),
        state: Map.get(record, :state, :unknown),
        entity: consent_entity(record)
      }
    }
  end

  defp consent_entity_type(%{group_id: group_id}) when is_binary(group_id), do: :group_id
  defp consent_entity_type(_record), do: :inbox_id

  defp consent_entity(%{group_id: group_id}) when is_binary(group_id), do: group_id
  defp consent_entity(%{entity: entity}) when is_binary(entity), do: entity
  defp consent_entity(_record), do: raise(ArgumentError, "invalid consent record")

  defp normalize_consent_records(records) when is_list(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, acc} ->
      case normalize_consent_record(record) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_consent_records(_records) do
    {:error, Error.invalid_argument("invalid consent records", %{})}
  end

  defp normalize_consent_record(%{group_id: group_id, state: state} = record)
       when is_binary(group_id) and state in [:unknown, :allowed, :denied] do
    if map_size(Map.take(record, [:group_id, :state])) == map_size(record) do
      {:ok, %{group_id: group_id, state: state}}
    else
      {:error, Error.invalid_argument("invalid consent record", %{record: record})}
    end
  end

  defp normalize_consent_record(%{entity: entity, state: state} = record)
       when is_binary(entity) and state in [:unknown, :allowed, :denied] do
    if map_size(Map.take(record, [:entity, :state])) == map_size(record) do
      {:ok, %{entity: entity, state: state}}
    else
      {:error, Error.invalid_argument("invalid consent record", %{record: record})}
    end
  end

  defp normalize_consent_record(record) do
    {:error, Error.invalid_argument("invalid consent record", %{record: record})}
  end

  defp generate_inbox_id(identifier, kind, nonce) do
    data = "#{identifier_key(identifier)}|#{kind}|#{nonce}"
    Base.encode16(:crypto.hash(:sha256, data), case: :lower) |> binary_part(0, 32)
  end

  defp inbox_clients(state, inbox_id) do
    state.clients
    |> Map.values()
    |> Enum.filter(&(&1.inbox_id == inbox_id))
  end

  defp fetch_inbox_states_by_ids(state, inbox_ids) do
    inbox_ids
    |> Enum.map(&fetch_inbox_state_by_inbox_id(state, &1))
    |> Enum.filter(&(&1 != nil))
  end

  defp fetch_inbox_state_by_inbox_id(state, inbox_id) do
    case inbox_clients(state, inbox_id) do
      [] -> nil
      [client | _] = clients -> build_inbox_state_from_clients(client, clients)
    end
  end

  defp build_inbox_state(client, state),
    do: build_inbox_state_from_clients(client, inbox_clients(state, client.inbox_id))

  defp build_inbox_state_from_clients(client, clients) do
    identifiers =
      clients
      |> Enum.flat_map(fn entry -> Enum.map(entry.account_identifiers, & &1.identifier) end)
      |> Enum.uniq()

    account_identifiers =
      clients
      |> Enum.flat_map(& &1.account_identifiers)
      |> Enum.uniq()

    installations =
      Enum.map(clients, fn entry ->
        %Installation{id: entry.installation_id, bytes: entry.installation_id_bytes}
      end)

    %InboxState{
      inbox_id: client.inbox_id,
      recovery_identifier: client.recovery_identifier.identifier,
      identifiers: identifiers,
      installation_ids: Enum.map(clients, & &1.installation_id),
      account_identifiers: account_identifiers,
      installations: installations
    }
  end

  defp apply_signature_request_action(state, %{action: :register, client_id: client_id}, _signer) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        %{state | clients: Map.put(state.clients, client_id, %{client | registered?: true})}

      :error ->
        state
    end
  end

  defp apply_signature_request_action(
         state,
         %{action: :add_account, client_id: client_id, data: %{identifier: identifier}},
         _signer
       ) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        updated = %{
          client
          | account_identifiers: Enum.uniq([identifier | client.account_identifiers])
        }

        %{
          state
          | clients: Map.put(state.clients, client_id, updated),
            clients_by_identifier:
              Map.put(state.clients_by_identifier, identifier_key(identifier), client.inbox_id)
        }

      :error ->
        state
    end
  end

  defp apply_signature_request_action(
         state,
         %{action: :remove_account, client_id: client_id, data: %{identifier: identifier}},
         _signer
       ) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        updated = %{
          client
          | account_identifiers: Enum.reject(client.account_identifiers, &(&1 == identifier))
        }

        %{
          state
          | clients: Map.put(state.clients, client_id, updated),
            clients_by_identifier:
              Map.delete(state.clients_by_identifier, identifier_key(identifier))
        }

      :error ->
        state
    end
  end

  defp apply_signature_request_action(
         state,
         %{action: :revoke_all_other_installations, client_id: client_id},
         _signer
       ) do
    with {:ok, client} <- fetch_client_from_state(state, client_id) do
      remaining_clients =
        state.clients
        |> Enum.reject(fn {id, other} ->
          id != client_id and other.inbox_id == client.inbox_id
        end)
        |> Map.new()

      remaining_identifiers =
        state.clients_by_identifier
        |> Enum.reject(fn {_key, inbox_id} -> inbox_id == client.inbox_id end)
        |> Map.new()

      %{
        state
        | clients: Map.put(remaining_clients, client_id, client),
          clients_by_identifier:
            Map.merge(remaining_identifiers, %{
              identifier_key(client.identifier) => client.inbox_id
            })
      }
    else
      {:error, _} -> state
    end
  end

  defp apply_signature_request_action(
         state,
         %{action: :revoke_installations, data: %{installation_ids: installation_ids}},
         _signer
       ) do
    clients =
      state.clients
      |> Enum.reject(fn {_id, client} -> client.installation_id in installation_ids end)
      |> Map.new()

    %{state | clients: clients}
  end

  defp apply_signature_request_action(
         state,
         %{
           action: :change_recovery_identifier,
           client_id: client_id,
           data: %{identifier: identifier}
         },
         _signer
       ) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        previous_identifier = identifier_key(client.recovery_identifier)
        updated = %{client | recovery_identifier: identifier}

        clients_by_identifier =
          state.clients_by_identifier
          |> Map.delete(previous_identifier)
          |> Map.put(identifier_key(identifier), client.inbox_id)

        %{
          state
          | clients: Map.put(state.clients, client_id, updated),
            clients_by_identifier: clients_by_identifier
        }

      :error ->
        state
    end
  end

  defp apply_signature_request_action(state, _request, _signer), do: state
end
