defmodule SiwaKeyring.HostedIdentity do
  @moduledoc "Encrypted persistent signers for account connections; no key export or transactions."

  alias SiwaKeyring.Keystore

  def ensure(identity_key) do
    with {:ok, config} <- config(identity_key),
         :ok <- ensure_wallet(config),
         {:ok, address} <- Keystore.get_address(config) do
      {:ok, %{address: address}}
    end
  end

  def signer(identity_key) do
    with {:ok, config} <- config(identity_key),
         {:ok, address} <- Keystore.get_address(config) do
      {:ok,
       Siwa.RemoteSigner.new(
         address: address,
         sign_message: fn message ->
           with {:ok, wallet} <- Keystore.get_wallet(config) do
             Siwa.EvmPersonalSign.sign_personal_signature(wallet["private_key"], message)
           end
         end
       )}
    end
  end

  defp config(identity_key) when is_binary(identity_key) do
    if Regex.match?(~r/\A[a-f0-9]{64}\z/, identity_key) do
      base = Application.fetch_env!(:siwa_keyring, :path)
      password = Application.fetch_env!(:siwa_keyring, :password)

      if is_binary(base) and base != "" and is_binary(password) and password != "" do
        {:ok, %{path: Path.join(base <> ".hosted", identity_key <> ".bin"), password: password}}
      else
        {:error, :hosted_identity_unavailable}
      end
    else
      {:error, :hosted_identity_unavailable}
    end
  end

  defp config(_), do: {:error, :hosted_identity_unavailable}

  defp ensure_wallet(config) do
    with :ok <- File.mkdir_p(Path.dirname(config.path)),
         :ok <- File.chmod(Path.dirname(config.path), 0o700) do
      if Keystore.has_wallet?(config) do
        :ok
      else
        case Keystore.create_wallet(config) do
          {:ok, _} -> :ok
          {:error, :wallet_already_exists} -> :ok
          error -> error
        end
      end
    end
  end
end
