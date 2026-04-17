defmodule Siwa.TransactionSigner do
  @callback sign_transaction(term(), map()) :: {:ok, map()} | {:error, term()}
  @callback sign_authorization(term(), map()) :: {:ok, map()} | {:error, term()}
end
