defmodule Siwa.Verify do
  alias Siwa.{Crypto, Message, Nonce, Receipt, Registry}

  def sign_message(fields, signer) do
    with {:ok, address} <- signer_module(signer).get_address(signer) do
      fields =
        case Map.get(fields, :address) || Map.get(fields, "address") do
          nil -> Map.put(fields, :address, address)
          _ -> fields
        end

      message = Message.build(fields)

      with {:ok, signature} <- signer_module(signer).sign_message(signer, message) do
        {:ok, %{message: message, signature: signature}}
      end
    end
  end

  @doc """
  Verifies a signed SIWA message and returns the authentication outcome.

  Accepts either the raw message string or a fields map, plus the signature
  produced by the signer. Validation covers, in order: message parsing, the
  expected `:domain`, the expiration/not-before time window, the signature
  (and that the recovered address matches the message address), nonce
  consumption, and agent registration checks.

  All outcomes are returned as `{:ok, map}` with a `:status` key:

  - `"authenticated"` — every check passed. The map includes `:address`,
    `:agent_id`, `:agent_registry`, `:nonce`, `:signer_type`, `:profile`,
    `:receipt`, and `:receipt_expires_at`.
  - `"not_registered"` — the signature was valid but the agent is not
    registered in the on-chain registry. The map includes an `:action`
    describing the `"register_agent"` step to take before retrying.
  - `"rejected"` — any other failed check. The map includes a `:reason`
    string (for example `"domain_mismatch"`, `"message_expired"`,
    `"message_not_yet_valid"`, `"address_mismatch"`, `"invalid_signature"`,
    nonce errors such as `"nonce_expired"` or `"nonce_address_mismatch"`,
    or registration errors such as `"owner_mismatch"`, `"inactive_agent"`,
    `"missing_required_services"`, or `"missing_required_trust_model"`).
    Non-atom internal errors are reported as `"invalid_request"`.

  Options include `:domain`, `:now`, `:audience`, `:nonce_token`,
  `:signature_validator`, `:profile_resolver`, `:chain_client`,
  `:require_active`, `:required_services`, and `:required_trust_models`.
  """
  def verify(message_or_fields, signature, opts \\ []) do
    with {:ok, fields, message} <- normalize_message(message_or_fields),
         :ok <- validate_domain(fields, opts),
         :ok <- validate_time_window(fields, opts),
         {:ok, verified_signature} <- validate_signature(signature, message, fields, opts),
         {:ok, nonce_entry} <- validate_nonce(fields, opts),
         {:ok, profile} <- validate_registration(fields, verified_signature, opts),
         {:ok, registry} <- Registry.parse_agent_registry(fields.agent_registry),
         {:ok, audience} <- nonce_audience(nonce_entry) do
      nonce_value = nonce_entry[:nonce] || nonce_entry["nonce"]

      receipt_payload = %{
        "typ" => "siwa_receipt",
        "jti" => Siwa.Nonce.generate_nonce(16),
        "sub" => verified_signature.address,
        "aud" => audience,
        "chain_id" => fields.chain_id,
        "nonce" => nonce_value,
        "key_id" => verified_signature.address,
        "registry_address" => registry.address,
        "token_id" => Integer.to_string(fields.agent_id)
      }

      with {:ok, receipt} <- Receipt.create(receipt_payload, opts) do
        {:ok,
         %{
           status: "authenticated",
           address: verified_signature.address,
           agent_id: fields.agent_id,
           agent_registry: fields.agent_registry,
           nonce: nonce_value,
           signer_type: verified_signature.signer_type,
           profile: profile,
           receipt: receipt.token,
           receipt_expires_at: DateTime.to_iso8601(receipt.expires_at)
         }}
      end
    else
      {:error, :not_registered} ->
        {:ok,
         %{
           status: "not_registered",
           action: %{
             type: "register_agent",
             message: "Register this agent before trying again."
           }
         }}

      {:error, reason} ->
        {:ok,
         %{
           status: "rejected",
           reason: rejection_reason(reason)
         }}
    end
  end

  defp normalize_message(message) when is_binary(message) do
    with {:ok, fields} <- Message.parse(message) do
      {:ok, fields, message}
    end
  end

  defp normalize_message(fields) when is_map(fields) do
    normalized = Message.normalize_fields(fields)
    {:ok, normalized, Message.build(normalized)}
  end

  defp validate_domain(fields, opts) do
    case Keyword.get(opts, :domain) do
      nil -> :ok
      expected when expected == fields.domain -> :ok
      _ -> {:error, :domain_mismatch}
    end
  end

  defp validate_time_window(fields, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with :ok <- validate_expiration_time(fields, now),
         :ok <- validate_not_before(fields, now) do
      :ok
    end
  end

  defp validate_nonce(fields, opts) do
    Nonce.consume(
      %{
        address: fields.address,
        agent_id: fields.agent_id,
        agent_registry: fields.agent_registry,
        nonce: fields.nonce,
        audience: Keyword.get(opts, :audience)
      },
      opts
    )
  end

  defp nonce_audience(%{audience: audience}) when is_binary(audience), do: {:ok, audience}
  defp nonce_audience(%{"audience" => audience}) when is_binary(audience), do: {:ok, audience}
  defp nonce_audience(_entry), do: {:error, :nonce_audience_missing}

  defp validate_expiration_time(fields, now) do
    case fields[:expiration_time] do
      nil ->
        :ok

      expiration_time ->
        with {:ok, parsed, _offset} <- DateTime.from_iso8601(expiration_time) do
          if DateTime.compare(now, parsed) == :gt, do: {:error, :message_expired}, else: :ok
        else
          _ -> {:error, :invalid_message_time}
        end
    end
  end

  defp validate_not_before(fields, now) do
    case fields[:not_before] do
      nil ->
        :ok

      not_before ->
        with {:ok, parsed, _offset} <- DateTime.from_iso8601(not_before) do
          if DateTime.compare(now, parsed) == :lt, do: {:error, :message_not_yet_valid}, else: :ok
        else
          _ -> {:error, :invalid_message_time}
        end
    end
  end

  defp validate_signature(signature, message, fields, opts) do
    with {:ok, verified} <- run_signature_validation(signature, message, opts),
         true <- String.downcase(verified.address) == String.downcase(fields.address) do
      {:ok, verified}
    else
      false -> {:error, :address_mismatch}
      error -> error
    end
  end

  defp run_signature_validation(signature, message, opts) do
    case Keyword.get(opts, :signature_validator) do
      nil -> Crypto.verify_personal_message(signature, message)
      fun when is_function(fun, 2) -> fun.(signature, message)
      module -> module.verify(signature, message, opts)
    end
  end

  defp validate_registration(fields, verified_signature, opts) do
    case Keyword.get(opts, :profile_resolver) do
      nil -> default_profile_resolution(fields, verified_signature, opts)
      fun when is_function(fun, 2) -> fun.(fields, verified_signature)
      module -> module.resolve(fields, verified_signature, opts)
    end
  end

  defp default_profile_resolution(fields, verified_signature, opts) do
    with {:ok, registry} <- Registry.parse_agent_registry(fields.agent_registry),
         client when not is_nil(client) <- Keyword.get(opts, :chain_client),
         {:ok, profile} <-
           Registry.get_agent(fields.agent_id,
             client: client,
             registry_address: registry.address,
             fetch_metadata: true
           ),
         :ok <- ensure_profile_owner(profile, verified_signature.address),
         :ok <- ensure_profile_matches(profile, opts) do
      {:ok, profile}
    else
      nil -> {:ok, %{owner: verified_signature.address, metadata: nil}}
      {:error, :agent_not_found} -> {:error, :not_registered}
      error -> error
    end
  end

  defp ensure_profile_owner(profile, address) do
    if String.downcase(profile.owner) == String.downcase(address),
      do: :ok,
      else: {:error, :owner_mismatch}
  end

  defp ensure_profile_matches(profile, opts) do
    metadata = profile.metadata || %{}
    services = Map.get(metadata, "services", [])
    active = Map.get(metadata, "active", true)
    trust = Map.get(metadata, "supportedTrust", [])

    cond do
      Keyword.get(opts, :require_active, false) and active != true ->
        {:error, :inactive_agent}

      missing_services?(Keyword.get(opts, :required_services, []), services) ->
        {:error, :missing_required_services}

      missing_trust?(Keyword.get(opts, :required_trust_models, []), trust) ->
        {:error, :missing_required_trust_model}

      true ->
        :ok
    end
  end

  defp missing_services?([], _services), do: false

  defp missing_services?(required, services) do
    names = Enum.map(services, &Map.get(&1, "name"))
    Enum.any?(required, &(&1 not in names))
  end

  defp missing_trust?([], _trust), do: false
  defp missing_trust?(required, trust), do: Enum.any?(required, &(&1 not in trust))

  defp rejection_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp rejection_reason(_reason), do: "invalid_request"

  defp signer_module(%module{}), do: module
end
