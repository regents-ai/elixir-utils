defmodule SiwaKeyring do
  alias SiwaKeyring.Service

  def create_wallet, do: Service.create_wallet([])
  def create_wallet(opts), do: Service.create_wallet(opts)

  def has_wallet?, do: Service.has_wallet?([])
  def has_wallet?(opts), do: Service.has_wallet?(opts)

  def get_address, do: Service.get_address([])
  def get_address(opts), do: Service.get_address(opts)

  def sign_message(message), do: Service.sign_message(message, [])
  def sign_message(message, opts), do: Service.sign_message(message, opts)

  def sign_raw_message(payload), do: Service.sign_raw_message(payload, [])
  def sign_raw_message(payload, opts), do: Service.sign_raw_message(payload, opts)

  def sign_transaction(tx), do: Service.sign_transaction(tx, [])
  def sign_transaction(tx, opts), do: Service.sign_transaction(tx, opts)

  def sign_authorization(auth), do: Service.sign_authorization(auth, [])
  def sign_authorization(auth, opts), do: Service.sign_authorization(auth, opts)
end
