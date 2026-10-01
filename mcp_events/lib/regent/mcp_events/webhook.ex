defmodule Regent.MCPEvents.Webhook do
  @moduledoc "Standard Webhooks signatures over the exact bytes sent to the callback."

  @doc "Returns decoded key bytes. Never log the returned value."
  def validate_secret("whsec_" <> encoded) do
    case Base.decode64(encoded) do
      {:ok, key} when byte_size(key) in 24..64 -> {:ok, key}
      _ -> {:error, :invalid_secret}
    end
  end

  def validate_secret(_), do: {:error, :invalid_secret}

  @doc "Signs one serialized body with current and optional rotation keys."
  def headers(
        subscription_id,
        message_id,
        body,
        secrets,
        timestamp \\ System.system_time(:second)
      ) do
    with true <- safe_id?(subscription_id) and safe_id?(message_id),
         true <- is_binary(body) and is_integer(timestamp) and timestamp >= 0,
         {:ok, keys} <- decode_secrets(secrets) do
      timestamp = Integer.to_string(timestamp)
      signed = message_id <> "." <> timestamp <> "." <> body

      signatures =
        Enum.map_join(keys, " ", fn key ->
          "v1," <> Base.encode64(:crypto.mac(:hmac, :sha256, key, signed))
        end)

      {:ok,
       [
         {"content-type", "application/json"},
         {"webhook-id", message_id},
         {"webhook-timestamp", timestamp},
         {"webhook-signature", signatures},
         {"x-mcp-subscription-id", subscription_id}
       ]}
    else
      false -> {:error, :invalid_webhook}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Compares fixed-length challenges without revealing their first differing byte."
  def secure_compare(left, right) when is_binary(left) and is_binary(right) do
    byte_size(left) == byte_size(right) and :crypto.hash_equals(left, right)
  end

  def secure_compare(_, _), do: false

  defp safe_id?(id) when is_binary(id),
    do: byte_size(id) in 1..200 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, id)

  defp safe_id?(_), do: false

  defp decode_secrets(secrets) when is_list(secrets) and length(secrets) in 1..2 do
    Enum.reduce_while(secrets, {:ok, []}, fn secret, {:ok, keys} ->
      case validate_secret(secret) do
        {:ok, key} -> {:cont, {:ok, keys ++ [key]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp decode_secrets(_), do: {:error, :invalid_secret}
end
