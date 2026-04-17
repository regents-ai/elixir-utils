defmodule SiwaKeyring.Auth do
  @drift_ms 30_000

  def compute_hmac(secret, method, path, body, timestamp \\ nil) do
    timestamp = timestamp || Integer.to_string(System.system_time(:millisecond))
    payload = [String.upcase(method), path, timestamp, body] |> Enum.join("\n")

    signature =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    %{
      "x-keyring-timestamp" => timestamp,
      "x-keyring-signature" => signature
    }
  end

  def verify_hmac(secret, method, path, body, timestamp, signature) do
    with {ts, ""} <- Integer.parse(to_string(timestamp)),
         true <- abs(System.system_time(:millisecond) - ts) <= @drift_ms do
      expected = compute_hmac(secret, method, path, body, to_string(timestamp))["x-keyring-signature"]

      if Plug.Crypto.secure_compare(expected, to_string(signature)) do
        :ok
      else
        {:error, :signature_mismatch}
      end
    else
      _ -> {:error, :stale_or_invalid_timestamp}
    end
  end
end
