defmodule SiwaKeyring.ProxySigner do
  @behaviour Siwa.Signer
  @behaviour Siwa.TransactionSigner

  defstruct [:client]

  def new(client), do: %__MODULE__{client: client}

  @impl true
  def get_address(%__MODULE__{client: client}) do
    with {:ok, %{"address" => address}} <- SiwaKeyring.Client.get_address(client) do
      {:ok, address}
    end
  end

  @impl true
  def sign_message(%__MODULE__{client: client}, message) do
    with {:ok, %{"signature" => signature}} <- SiwaKeyring.Client.sign_message(client, message) do
      {:ok, signature}
    end
  end

  @impl true
  def sign_raw_message(%__MODULE__{client: client}, payload) do
    with {:ok, %{"signature" => signature}} <- SiwaKeyring.Client.sign_raw_message(client, payload) do
      {:ok, signature}
    end
  end

  @impl true
  def sign_transaction(%__MODULE__{client: client}, tx), do: SiwaKeyring.Client.sign_transaction(client, tx)

  @impl true
  def sign_authorization(%__MODULE__{client: client}, authorization),
    do: SiwaKeyring.Client.sign_authorization(client, authorization)
end
