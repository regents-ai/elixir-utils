defmodule Siwa.Plug do
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    request = %{
      method: conn.method,
      path: conn.request_path,
      host: conn.host,
      query: conn.query_string,
      body: conn.private[:raw_body] || conn.assigns[:raw_body] || "",
      headers: Map.new(conn.req_headers)
    }

    case Siwa.verify_authenticated_request(request, opts) do
      {:ok, agent} ->
        assign(conn, :siwa_agent, agent)

      {:error, reason} ->
        conn
        |> send_resp(401, Jason.encode!(%{status: "rejected", reason: inspect(reason)}))
        |> halt()
    end
  end
end
