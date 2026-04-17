defmodule Siwa.Signer do
  @callback get_address(term()) :: {:ok, binary()} | {:error, term()}
  @callback sign_message(term(), binary()) :: {:ok, map()} | {:error, term()}
  @callback sign_raw_message(term(), binary()) :: {:ok, map()} | {:error, term()}
end
