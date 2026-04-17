defmodule Siwa.CaptchaPolicy do
  @callback challenge(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback verify(map(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
end
