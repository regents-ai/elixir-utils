defmodule SiwaKeyring.HostedIdentity do
  @moduledoc """
  Signers for hosted account connections. Each connection's key is an encrypted
  wallet that the caller stores where it likes; the key is never exported and
  signs only messages, never transactions.
  """

  alias SiwaKeyring.Keystore

  @doc "A new signing key, encrypted with `password`, for the caller to store."
  @spec new(String.t()) :: {:ok, String.t()} | {:error, term()}
  def new(password) do
    with {:ok, wallet} <- Keystore.new_wallet() do
      {:ok, Keystore.encrypt_wallet(wallet, password)}
    end
  end

  @doc "The signer of a key made by `new/1`."
  @spec signer(String.t(), String.t()) :: {:ok, %Siwa.RemoteSigner{}} | {:error, term()}
  def signer(encrypted, password) do
    with {:ok, wallet} <- Keystore.decrypt_wallet(encrypted, password) do
      {:ok,
       Siwa.RemoteSigner.new(
         address: wallet["address"],
         sign_message: fn message ->
           with {:ok, wallet} <- Keystore.decrypt_wallet(encrypted, password) do
             Siwa.EvmPersonalSign.sign_personal_signature(wallet["private_key"], message)
           end
         end
       )}
    end
  end
end
