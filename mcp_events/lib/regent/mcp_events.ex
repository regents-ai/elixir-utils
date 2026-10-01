defmodule Regent.MCPEvents do
  @moduledoc """
  MCP 2026-07-28 event protocol helpers. Products own event definitions,
  authorization, subscriptions and the durable event outbox.

  Event maps use the protocol's string keys. Subscription maps use atom keys.
  Callback secrets and signatures must never appear in logs.
  """

  alias Regent.MCPEvents.{Callback, Webhook}

  @max_body_bytes 262_144

  @doc "Returns the server/discover result with event support enabled."
  def discover(capabilities \\ %{}) do
    %{
      "resultType" => "complete",
      "supportedVersions" => ["2026-07-28"],
      "capabilities" => Map.put(capabilities, "events", %{})
    }
  end

  @doc "Derives an owner-bound identity with recursively sorted JSON object keys."
  def subscription_id(owner_id, name, arguments, url)
      when is_binary(owner_id) and owner_id != "" and is_binary(name) and name != "" and
             is_map(arguments) do
    with {:ok, _uri} <- validate_callback(url),
         {:ok, json} <- canonical_json([owner_id, name, arguments, url]) do
      {:ok, "sub_" <> Base.url_encode64(:crypto.hash(:sha256, json), padding: false)}
    end
  end

  def subscription_id(_, _, _, _), do: {:error, :invalid_identity}

  @doc "Validates a whsec_ base64 secret containing 24–64 bytes."
  defdelegate validate_secret(secret), to: Webhook

  @doc "Checks URL syntax and blocks non-public literal destinations. DNS is checked at connection time."
  defdelegate validate_callback(url), to: Callback, as: :validate

  @doc "Verifies a callback once using a fresh challenge, before any application data is sent."
  def verify_callback(id, url, secret) do
    challenge = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    message_id =
      "msg_verification_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    body = Jason.encode!(%{"type" => "verification", "challenge" => challenge})

    with {:ok, headers} <- Webhook.headers(id, message_id, body, [secret]),
         {:ok, %{status: status, body: response}} <- Callback.post(url, body, headers),
         true <- status in 200..299,
         {:ok, %{"challenge" => echoed}} when is_binary(echoed) <- Jason.decode(response),
         true <- Webhook.secure_compare(challenge, echoed) do
      :ok
    else
      {:error, %Jason.DecodeError{}} -> {:error, :challenge_failed}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :challenge_failed}
    end
  end

  @doc "Maps callback failures to the protocol's categorized JSON-RPC error."
  def callback_error(reason) do
    %{
      "code" => -32015,
      "message" => "Callback verification failed",
      "data" => %{"reason" => callback_reason(reason)}
    }
  end

  @doc "Sends one event. Authorization must be rechecked by the product immediately before this call."
  def deliver(%{id: id, name: name, url: url, secret: secret} = subscription, event)
      when is_binary(id) and is_binary(name) and is_binary(url) and is_binary(secret) do
    with :ok <- validate_event(subscription, event),
         {:ok, body} <- encode_event(event),
         {:ok, headers} <-
           Webhook.headers(subscription.id, event["eventId"], body, signing_secrets(subscription)),
         {:ok, response} <- Callback.post_event(subscription.url, body, headers) do
      classify_status(response.status)
    else
      {:error, reason} -> classify_error(reason)
    end
  end

  def deliver(_, _), do: {:stop, :invalid_subscription}

  @doc "Serializes one complete envelope and enforces the protocol's 256 KiB limit."
  def encode_event(event) do
    with {:ok, body} <- Jason.encode(event),
         true <- byte_size(body) <= @max_body_bytes do
      {:ok, body}
    else
      false -> {:error, :payload_too_large}
      {:error, _} -> {:error, :invalid_event}
    end
  end

  @doc "Classifies HTTP acknowledgement and permanent or transient failures."
  def classify_status(status) when status in 200..299, do: :ok
  def classify_status(410), do: {:stop, :gone}
  def classify_status(413), do: {:stop, :payload_too_large}

  def classify_status(status) when status in [408, 425, 429] or status in 500..599,
    do: {:retry, {:http_status, status}}

  def classify_status(status), do: {:stop, {:http_status, status}}

  @doc "Canonical JSON for identities; accepts JSON values and string-keyed objects only."
  def canonical_json(value) do
    try do
      {:ok, value |> canonical_value() |> Jason.encode!()}
    rescue
      _ in [ArgumentError, Jason.EncodeError] -> {:error, :invalid_json}
    end
  end

  defp canonical_value(value) when is_map(value) and not is_struct(value) do
    if Enum.all?(Map.keys(value), &is_binary/1) do
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} -> {key, canonical_value(item)} end)
      |> Jason.OrderedObject.new()
    else
      raise ArgumentError, "JSON object keys must be strings"
    end
  end

  defp canonical_value(value) when is_list(value), do: Enum.map(value, &canonical_value/1)

  defp canonical_value(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: value

  defp canonical_value(_), do: raise(ArgumentError, "Expected JSON data")

  defp validate_event(
         subscription,
         %{
           "eventId" => id,
           "name" => name,
           "timestamp" => timestamp,
           "data" => data,
           "cursor" => cursor
         } = event
       )
       when is_binary(id) and is_binary(name) and is_binary(timestamp) and is_map(data) and
              (is_binary(cursor) or is_nil(cursor)) do
    with true <-
           Map.keys(event) |> Enum.sort() == ["cursor", "data", "eventId", "name", "timestamp"],
         true <- name == Map.get(subscription, :name),
         {:ok, _datetime, _offset} <- DateTime.from_iso8601(timestamp),
         {:ok, _} <- canonical_json(data) do
      :ok
    else
      _ -> {:error, :invalid_event}
    end
  end

  defp validate_event(_, _), do: {:error, :invalid_event}

  defp signing_secrets(subscription) do
    case subscription do
      %{previous_secret: old, secret_rotation_expires_at: %DateTime{} = until}
      when is_binary(old) ->
        if DateTime.compare(until, DateTime.utc_now()) == :gt,
          do: [subscription.secret, old],
          else: [subscription.secret]

      _ ->
        [subscription.secret]
    end
  end

  defp classify_error(reason) when reason in [:timeout, :dns_error, :connection_error],
    do: {:retry, reason}

  defp classify_error(reason), do: {:stop, reason}

  defp callback_reason(reason) when reason in [:timeout, :challenge_failed],
    do: Atom.to_string(reason)

  defp callback_reason(:dns_error), do: "dns_error"
  defp callback_reason(:connection_error), do: "connection_error"
  defp callback_reason(_), do: "invalid_callback"
end
