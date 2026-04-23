defmodule Siwa.ClientResolver do
  alias Siwa.{LocalSigner, RemoteSigner}

  def resolve_signer(%{provider: :local} = config) do
    with {:ok, signer} <- LocalSigner.new(signer_type: Map.get(config, :signer_type, "eoa")) do
      {:ok, signer}
    end
  end

  def resolve_signer(%{provider: :remote} = config) do
    {:ok,
     RemoteSigner.new(
       address: config.address,
       sign_message: config.sign_message,
       sign_raw_message: config[:sign_raw_message],
       sign_transaction: config[:sign_transaction],
       sign_authorization: config[:sign_authorization]
     )}
  end

  def resolve_signer(%{provider: provider} = config)
      when provider in [:circle, :openfort, :privy, :bankr] do
    resolve_signer(%{config | provider: :remote})
  end

  def resolve_signer(_), do: {:error, :unknown_signer_provider}
end
