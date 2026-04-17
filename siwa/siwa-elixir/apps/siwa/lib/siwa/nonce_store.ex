defmodule Siwa.NonceStore do
  @callback put(binary(), binary(), map()) :: :ok | {:error, term()}
  @callback consume(binary(), binary()) :: {:ok, map()} | {:error, term()}
end
