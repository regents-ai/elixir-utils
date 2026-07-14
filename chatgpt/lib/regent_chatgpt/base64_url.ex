defmodule RegentChatGPT.Base64Url do
  @moduledoc false

  @spec encode(binary()) :: String.t()
  def encode(value), do: Base.url_encode64(value, padding: false)

  @spec decode(String.t()) :: {:ok, binary()} | :error
  def decode(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> Base.url_decode64(value)
    end
  end
end
