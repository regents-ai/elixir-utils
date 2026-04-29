defmodule SiwaKeyring.Keystore do
  alias Siwa.LocalSigner

  def create_wallet(config) do
    with {:ok, _path} <- wallet_path(config),
         {:ok, signer} <- LocalSigner.new() do
      wallet = %{
        private_key: signer.private_key,
        public_key: signer.public_key,
        address: signer.address,
        signer_type: signer.signer_type
      }

      with :ok <- persist_wallet(config, wallet) do
        {:ok, public_wallet(wallet)}
      end
    end
  end

  def has_wallet?(config) do
    case wallet_path(config) do
      {:ok, path} -> File.exists?(path)
      {:error, :wallet_missing} -> false
    end
  end

  def get_wallet(config) do
    with {:ok, path} <- wallet_path(config),
         true <- File.exists?(path),
         {:ok, encrypted} <- File.read(path),
         {:ok, wallet} <- decrypt_wallet(encrypted, config.password) do
      {:ok, wallet}
    else
      false -> {:error, :wallet_missing}
      error -> error
    end
  end

  def get_address(config) do
    with {:ok, wallet} <- get_wallet(config) do
      {:ok, wallet["address"] || wallet[:address]}
    end
  end

  def persist_wallet(config, wallet) do
    with {:ok, path} <- wallet_path(config),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      encrypted = encrypt_wallet(wallet, config.password)
      write_new_wallet(path, encrypted)
    end
  end

  def encrypt_wallet(wallet, password) do
    iv = :crypto.strong_rand_bytes(12)
    salt = :crypto.strong_rand_bytes(16)
    key = :crypto.pbkdf2_hmac(:sha256, password, salt, 100_000, 32)
    plaintext = Jason.encode!(wallet)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "siwa-keyring", true)

    Jason.encode!(%{
      cipher: "aes-256-gcm",
      ciphertext: Base.encode64(ciphertext),
      iv: Base.encode64(iv),
      tag: Base.encode64(tag),
      salt: Base.encode64(salt)
    })
  end

  def decrypt_wallet(blob, password) do
    decrypt_wallet_payload(blob, password)
  rescue
    _ -> {:error, :keystore_decrypt_failed}
  catch
    _, _ -> {:error, :keystore_decrypt_failed}
  end

  defp wallet_path(%{path: path}) when is_binary(path) and path != "", do: {:ok, path}
  defp wallet_path(_config), do: {:error, :wallet_missing}

  defp public_wallet(wallet) do
    Map.take(wallet, [:public_key, :address, :signer_type])
  end

  defp write_new_wallet(path, encrypted) do
    temp_path = path <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- write_temp_wallet(temp_path, encrypted),
         :ok <- File.chmod(temp_path, 0o600),
         :ok <- publish_new_file(temp_path, path) do
      :ok
    else
      {:error, :eexist} ->
        File.rm(temp_path)
        {:error, :wallet_already_exists}

      error ->
        File.rm(temp_path)
        error
    end
  end

  defp write_temp_wallet(temp_path, encrypted) do
    case File.open(temp_path, [:write, :exclusive, :binary], fn file ->
           :ok = File.chmod(temp_path, 0o600)
           IO.binwrite(file, encrypted)
         end) do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  defp publish_new_file(temp_path, path) do
    case File.ln(temp_path, path) do
      :ok ->
        with :ok <- File.chmod(path, 0o600) do
          File.rm(temp_path)
        end

      {:error, :eexist} = error ->
        error

      error ->
        error
    end
  end

  defp decrypt_wallet_payload(blob, password) do
    with {:ok, payload} <- Jason.decode(blob),
         :ok <- ensure_cipher(payload),
         {:ok, salt} <- fetch_base64(payload, "salt"),
         {:ok, iv} <- fetch_base64(payload, "iv"),
         {:ok, ciphertext} <- fetch_base64(payload, "ciphertext"),
         {:ok, tag} <- fetch_base64(payload, "tag"),
         key <- :crypto.pbkdf2_hmac(:sha256, password, salt, 100_000, 32),
         plaintext <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             iv,
             ciphertext,
             "siwa-keyring",
             tag,
             false
           ),
         true <- is_binary(plaintext),
         {:ok, wallet} <- Jason.decode(plaintext) do
      {:ok, wallet}
    else
      _ -> {:error, :keystore_decrypt_failed}
    end
  end

  defp ensure_cipher(%{"cipher" => "aes-256-gcm"}), do: :ok
  defp ensure_cipher(_payload), do: {:error, :invalid_cipher}

  defp fetch_base64(payload, key) do
    with value when is_binary(value) <- Map.get(payload, key),
         {:ok, decoded} <- Base.decode64(value) do
      {:ok, decoded}
    else
      _ -> {:error, :invalid_base64}
    end
  end
end
