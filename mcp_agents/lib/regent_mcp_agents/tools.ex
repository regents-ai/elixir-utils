defmodule RegentMCPAgents.Tools do
  @moduledoc "Shared MCP identity setup for an account-level ChatGPT connection."
  import Plug.Conn

  @names ~w(register_identity get_identity pair_identity)
  def names, do: @names

  def list do
    [
      tool(
        "register_identity",
        "Connect a Regents identity",
        "Prepare the persistent ChatGPT connection to your signed-in Regents identity. Reuses it across chats; does not pair, post or create another person account.",
        %{},
        [],
        false
      ),
      tool(
        "get_identity",
        "Check your connected identity",
        "Check whether this persistent ChatGPT connection is currently paired with your Regents identity. Does not change its permissions.",
        %{},
        [],
        true
      ),
      tool(
        "pair_identity",
        "Pair the connected identity",
        "Pair the ChatGPT connection with your signed-in Regents account using that account's current one-use pairing code. Requires explicit approval. Use only the approved pairing code; never request account credentials.",
        %{
          "code" => %{type: "string", minLength: 1, maxLength: 128},
          "name" => %{type: "string", minLength: 1, maxLength: 100}
        },
        ["code", "name"],
        false
      )
    ]
  end

  def required_scope(name) when name in @names, do: RegentMCPAgents.identity_scope()

  def required_scope(name) when name in ["ask_question", "post_reply"],
    do: RegentMCPAgents.posting_scope()

  def authorize(conn, name) do
    required = required_scope(name)

    with ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
         {:ok, principal} <- RegentOAuth.verify(bearer, RegentOAuth.resource(), required) do
      assign(conn, :mcp_agent_principal, principal)
    else
      _ ->
        challenge =
          RegentOAuth.challenge(required) <>
            ~s(, error="insufficient_scope", error_description="Connect your Regents account and approve this permission.")

        result = %{
          content: [
            %{type: "text", text: "Connect your Regents account and approve this permission."}
          ],
          isError: true,
          resultType: "complete",
          _meta: %{"mcp/www_authenticate" => [challenge]}
        }

        conn
        |> put_resp_header("www-authenticate", challenge)
        |> RegentOAuth.Protocol.json(200, %{
          jsonrpc: "2.0",
          id: conn.body_params["id"],
          result: result
        })
        |> halt()
    end
  end

  def call("register_identity", args, principal) when args == %{},
    do: RegentMCPAgents.register(principal)

  def call("get_identity", args, principal) when args == %{},
    do: RegentMCPAgents.status(principal)

  def call("pair_identity", args, principal), do: RegentMCPAgents.pair(principal, args)
  def call(_, _, _), do: {:error, :invalid_identity_request}

  def refusal do
    %{
      error: %{
        code: "identity_request_refused",
        message: "The identity request could not be completed.",
        hint:
          "Connect your Regents account, register the connection, and check its pairing on the account page. If a post timed out, read the thread before retrying with the same request key."
      }
    }
  end

  defp tool(name, title, description, properties, required, read_only?) do
    %{
      name: name,
      title: title,
      description: description,
      inputSchema: %{
        type: "object",
        properties: properties,
        required: required,
        additionalProperties: false
      },
      securitySchemes: [%{type: "oauth2", scopes: [RegentMCPAgents.identity_scope()]}],
      annotations: %{readOnlyHint: read_only?, destructiveHint: false, openWorldHint: false}
    }
  end
end
