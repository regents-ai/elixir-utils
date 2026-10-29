defmodule RegentMCPAgents.SiteTools do
  @moduledoc """
  A site's own tools at its MCP address, beside the shared identity tools: the
  operations the site's agents already have over signed HTTP, offered to a
  connected app. A call becomes the exact request a self-signing agent sends,
  signed by the connection's hosted signer and served in this process through
  the site's own endpoint (`RegentMCPAgents.act/5`), so the site's own
  verification, pairing, rights, limits and refusals decide it. A public read
  goes the same way, unsigned.

  The site names where its tools may send (`paths/0`); the library signs
  nothing outside those prefixes, and nothing with a query, a dot segment or an
  encoded slash.
  """

  @typedoc "One MCP tool: `name`, `title`, `description`, `inputSchema` and `annotations`."
  @type tool :: map()

  @typedoc """
  The request one call makes: signed as the connection's identity, or a public
  read sent unsigned. A GET carries no body; a POST's body is a map sent as JSON.
  Only a public read's path may end in a plain query, such as `?before=12`.
  """
  @type request ::
          {:signed | :public, method :: String.t(), path :: String.t(), body :: map() | nil}

  @doc "The permission every site tool needs: one of the site's OAuth scopes."
  @callback scope() :: String.t()

  @doc "The path prefixes the site's signed operations and its public reads live under."
  @callback paths() :: %{signed: [String.t()], public: [String.t()]}

  @doc "Every site tool, in the order `tools/list` shows them after the identity tools."
  @callback list() :: [tool()]

  @doc """
  The request a call of `name` with `arguments` makes; `{:refused, error}`, an
  `{"code", "message", "hint"}` map, for arguments that can't make one; or
  `:unknown` when `name` is no site tool.
  """
  @callback request(name :: String.t(), arguments :: map()) ::
              {:ok, request()} | {:refused, map()} | :unknown
end
