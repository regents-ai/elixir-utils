defmodule RegentChatGPT.HTTP do
  @moduledoc """
  HTTP client boundary used by RegentChatGPT.

  Callers may pass a module implementing this behaviour or a one-argument
  function in `RegentChatGPT.Config.resolve/1`.
  """

  @callback request(keyword()) :: {:ok, map()} | {:error, term()}

  @spec request(RegentChatGPT.Config.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(%RegentChatGPT.Config{http_client: client}, opts) when is_function(client, 1) do
    client.(opts)
  end

  def request(%RegentChatGPT.Config{http_client: client}, opts) when is_atom(client) do
    client.request(opts)
  end

  defmodule ReqClient do
    @moduledoc false
    @behaviour RegentChatGPT.HTTP

    @impl true
    def request(opts) when is_list(opts) do
      with {:ok, _started} <- Application.ensure_all_started(:req) do
        Req.request(opts)
      end
    end
  end
end
