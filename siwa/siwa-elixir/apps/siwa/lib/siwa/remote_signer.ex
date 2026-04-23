defmodule Siwa.RemoteSigner do
  @behaviour Siwa.Signer
  @behaviour Siwa.TransactionSigner

  defstruct [
    :address,
    :sign_message_fun,
    :sign_raw_fun,
    :sign_transaction_fun,
    :sign_authorization_fun
  ]

  def new(opts) do
    %__MODULE__{
      address: Keyword.fetch!(opts, :address),
      sign_message_fun: Keyword.fetch!(opts, :sign_message),
      sign_raw_fun: Keyword.get(opts, :sign_raw_message),
      sign_transaction_fun: Keyword.get(opts, :sign_transaction),
      sign_authorization_fun: Keyword.get(opts, :sign_authorization)
    }
  end

  @impl true
  def get_address(%__MODULE__{address: address}), do: {:ok, address}

  @impl true
  def sign_message(%__MODULE__{sign_message_fun: fun}, message), do: fun.(message)

  @impl true
  def sign_raw_message(%__MODULE__{sign_raw_fun: nil}, payload),
    do: {:error, {:unsupported, :raw_signing, payload}}

  def sign_raw_message(%__MODULE__{sign_raw_fun: fun}, payload), do: fun.(payload)

  @impl true
  def sign_transaction(%__MODULE__{sign_transaction_fun: nil}, tx),
    do: {:error, {:unsupported, :transaction_signing, tx}}

  def sign_transaction(%__MODULE__{sign_transaction_fun: fun}, tx), do: fun.(tx)

  @impl true
  def sign_authorization(%__MODULE__{sign_authorization_fun: nil}, authorization),
    do: {:error, {:unsupported, :authorization_signing, authorization}}

  def sign_authorization(%__MODULE__{sign_authorization_fun: fun}, authorization),
    do: fun.(authorization)
end
