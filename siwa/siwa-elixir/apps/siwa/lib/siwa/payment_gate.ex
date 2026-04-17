defmodule Siwa.PaymentGate do
  @callback verify(map(), keyword()) :: {:ok, map()} | {:error, term()}
end
