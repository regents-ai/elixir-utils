defmodule Siwa.LocalSigner do
  @behaviour Siwa.Signer
  @behaviour Siwa.TransactionSigner

  defstruct [:private_key, :public_key, :address, signer_type: "eoa"]

  alias Siwa.Crypto

  def new(opts \\ []) do
    with {:ok, keypair} <- Crypto.generate_keypair() do
      {:ok,
       %__MODULE__{
         private_key: keypair.private_key,
         public_key: keypair.public_key,
         address: Keyword.get(opts, :address, keypair.address),
         signer_type: Keyword.get(opts, :signer_type, "eoa")
       }}
    end
  end

  def from_private_key(private_key, public_key, opts \\ []) do
    %__MODULE__{
      private_key: private_key,
      public_key: public_key,
      address: Keyword.get_lazy(opts, :address, fn -> Crypto.address_from_public_key(Crypto.decode_hex!(public_key)) end),
      signer_type: Keyword.get(opts, :signer_type, "eoa")
    }
  end

  @impl true
  def get_address(%__MODULE__{address: address}), do: {:ok, address}

  @impl true
  def sign_message(%__MODULE__{} = signer, message) do
    Crypto.sign_personal_message(signer.private_key, message,
      public_key: signer.public_key,
      signer_type: signer.signer_type
    )
  end

  @impl true
  def sign_raw_message(%__MODULE__{} = signer, payload) do
    Crypto.sign_raw(signer.private_key, payload,
      public_key: signer.public_key,
      signer_type: signer.signer_type
    )
  end

  @impl true
  def sign_transaction(%__MODULE__{} = signer, tx) do
    payload = Jason.encode!(tx)

    with {:ok, signature} <- sign_raw_message(signer, payload) do
      {:ok, %{transaction: tx, signature: signature}}
    end
  end

  @impl true
  def sign_authorization(%__MODULE__{} = signer, authorization) do
    payload = Jason.encode!(authorization)

    with {:ok, signature} <- sign_raw_message(signer, payload) do
      {:ok, %{authorization: authorization, signature: signature}}
    end
  end
end
