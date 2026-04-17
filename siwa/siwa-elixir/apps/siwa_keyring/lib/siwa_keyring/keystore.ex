defmodule SiwaKeyring.Keystore do
  alias Siwa.LocalSigner

  def create_wallet(config) do
    with {:ok, signer} <- LocalSigner.new() do
      payload = %{
        private_key: signer.private_key,
        public_key: signer.public_key,
        address: signer.address,
        signer_type: signer.signer_type
      }

      :ok = persist_wallet(config, payload)
      {:ok, payload}
    end
  end

  def has_wallet?(config), do: File.exists?(config.path)

  def get_wallet(config) do
    with true <- has_wallet?(config),
         {:ok, encrypted} <- File.read(config.path),
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
    File.mkdir_p!(Path.dirname(config.path))
    encrypted = encrypt_wallet(wallet, config.password)
    File.write(config.path, encrypted)
  end

  def encrypt_wallet(wallet, password) do
    iv = :crypto.strong_rand_bytes(12)
    salt = :crypto.strong_rand_bytes(16)
    key = :crypto.pbkdf2_hmac(:sha256, password, salt, 100_000, 32)
    plaintext = Jason.encode!(wallet)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "siwa-keyring", true)

    Jason.encode!(%{
      cipher: "aes-256-gcm",
      ciphertext: Base.encode64(ciphertext),
      iv: Base.encode64(iv),
      tag: Base.encode64(tag),
      salt: Base.encode64(salt)
    })
  end

  def decrypt_wallet(blob, password) do
    with {:ok, payload} <- Jason.decode(blob),
         salt <- Base.decode64!(payload["salt"]),
         iv <- Base.decode64!(payload["iv"]),
         ciphertext <- Base.decode64!(payload["ciphertext"]),
         tag <- Base.decode64!(payload["tag"]),
         key <- :crypto.pbkdf2_hmac(:sha256, password, salt, 100_000, 32),
         plaintext <- :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, "siwa-keyring", tag, false),
         {:ok, wallet} <- Jason.decode(plaintext) do
      {:ok, wallet}
    else
      _ -> {:error, :keystore_decrypt_failed}
    end
  end
end
