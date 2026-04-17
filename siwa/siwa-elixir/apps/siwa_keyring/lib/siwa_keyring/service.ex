defmodule SiwaKeyring.Service do
  alias Siwa.LocalSigner
  alias SiwaKeyring.Keystore

  def create_wallet(opts \\ []) do
    config = config(opts)

    case Keystore.has_wallet?(config) do
      true -> {:error, :wallet_already_exists}
      false -> Keystore.create_wallet(config)
    end
  end

  def has_wallet?(opts \\ []) do
    {:ok, %{has_wallet: Keystore.has_wallet?(config(opts))}}
  end

  def get_address(opts \\ []) do
    Keystore.get_address(config(opts))
  end

  def sign_message(message, opts \\ []) do
    with {:ok, signer} <- signer_from_store(opts) do
      LocalSigner.sign_message(signer, message)
    end
  end

  def sign_raw_message(payload, opts \\ []) do
    with {:ok, signer} <- signer_from_store(opts) do
      LocalSigner.sign_raw_message(signer, payload)
    end
  end

  def sign_transaction(tx, opts \\ []) do
    with {:ok, signer} <- signer_from_store(opts) do
      LocalSigner.sign_transaction(signer, tx)
    end
  end

  def sign_authorization(authorization, opts \\ []) do
    with {:ok, signer} <- signer_from_store(opts) do
      LocalSigner.sign_authorization(signer, authorization)
    end
  end

  defp signer_from_store(opts) do
    with {:ok, wallet} <- Keystore.get_wallet(config(opts)) do
      {:ok,
       LocalSigner.from_private_key(
         wallet["private_key"],
         wallet["public_key"],
         address: wallet["address"],
         signer_type: wallet["signer_type"] || "eoa"
       )}
    end
  end

  defp config(opts) do
    env = Application.get_all_env(:siwa_keyring)

    %{
      path: Keyword.get(opts, :path, env[:path]),
      password: Keyword.get(opts, :password, env[:password])
    }
  end
end
