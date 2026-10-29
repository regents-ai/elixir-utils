defmodule RegentOAuth.ClientDocuments do
  @moduledoc """
  Apps that publish their own identity at an HTTPS address and use that address
  as their `client_id` (OAuth Client ID Metadata Documents,
  draft-ietf-oauth-client-id-metadata-document-02). Claude's is
  `https://claude.ai/oauth/mcp-oauth-client-metadata`.

  The document is read from its address, never from the request, and checked:
  its `client_id` is exactly the address, it is a public client (`none`), it can
  use the authorization code grant, and only its HTTPS callbacks on the
  address's own host are kept. It is then recorded as an ordinary public client
  row, with this table naming the address it came from, so codes, tokens and
  Connected apps work as for any other app.

  An address is resolved only through this table and a registered client id
  only through registration (`RegentOAuth.Protocol`): neither is ever taken for
  the other. Where a person is about to approve, a document older than its
  cache lifetime is read again first, and one that cannot be read refuses the
  request. A failed read is never stored.
  """

  import Ecto.Query
  alias Boruta.Ecto.Client
  alias RegentOAuth.Repo

  @max_bytes 5_120
  @min_age 300
  @default_age 3_600
  @max_age 86_400

  defmodule Document do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:url, :string, autogenerate: false}
    schema "oauth_client_documents" do
      field(:client_id, Ecto.UUID)
      field(:refresh_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end
  end

  @doc "Whether a `client_id` is a published identity's address rather than a registered client's id."
  def address?(value), do: is_binary(value) and String.starts_with?(value, "https://")

  @doc """
  The client recorded for the published identity at `url`, read again from its
  address first when it is due. For requests a person is about to approve.
  """
  def current(url) do
    with true <- client_id_url?(url) do
      case Repo.get(Document, url) do
        %Document{client_id: id, refresh_at: refresh_at} ->
          if DateTime.after?(refresh_at, DateTime.utc_now()), do: {:ok, id}, else: refresh(url)

        nil ->
          refresh(url)
      end
    else
      _ -> :error
    end
  end

  @doc "The client recorded for `url`, without reading the address. For token and revocation requests."
  def stored(url) do
    case address?(url) && Repo.get(Document, url) do
      %Document{client_id: id} -> {:ok, id}
      _ -> :error
    end
  end

  @doc "Whether a client row was recorded from a published identity."
  def document_client?(client_id),
    do: Repo.exists?(from(d in Document, where: d.client_id == ^client_id))

  defp refresh(url) do
    result =
      with {:ok, response} <-
             RegentHttp.Public.get(url,
               max_bytes: @max_bytes,
               headers: [{"accept", "application/json"}]
             ),
           {:ok, attrs} <- validate(url, response) do
        save(url, attrs, refresh_at(response.headers))
      else
        _ -> :error
      end

    :telemetry.execute([:regent_oauth, :client_document, :read], %{count: 1}, %{
      result: if(result == :error, do: :refused, else: :ok)
    })

    result
  end

  defp validate(url, %{status: 200, headers: headers, body: body}) do
    host = URI.parse(url).host

    with true <- json_type?(headers),
         {:ok, %{} = document} <- Jason.decode(body),
         true <- document["client_id"] == url,
         false <- Map.has_key?(document, "client_secret"),
         false <- Map.has_key?(document, "client_secret_expires_at"),
         "none" <- document["token_endpoint_auth_method"],
         true <- includes?(document, "grant_types", "authorization_code"),
         true <- includes?(document, "response_types", "code"),
         uris when is_list(uris) and length(uris) in 1..10 <- document["redirect_uris"],
         [_ | _] = kept <- uris |> Enum.filter(&own_callback?(&1, host)) |> Enum.uniq(),
         {:ok, name} <- name(document["client_name"], host) do
      {:ok, %{name: name, redirect_uris: kept}}
    else
      _ -> :error
    end
  end

  defp validate(_url, _response), do: :error

  # A document leaving these out means RFC 7591's defaults: the code grant and
  # the code response type.
  defp includes?(document, key, value) do
    case Map.get(document, key) do
      nil -> true
      list when is_list(list) -> Enum.all?(list, &is_binary/1) and value in list
      _ -> false
    end
  end

  # Only HTTPS callbacks on the address's own host: the publisher of the
  # identity is the one who receives its codes.
  defp own_callback?(uri, host) do
    RegentOAuth.Protocol.redirect_uri?(uri) and
      match?(%URI{scheme: "https", host: ^host}, URI.parse(uri))
  end

  defp name(nil, host), do: {:ok, host}

  defp name(name, _host) when is_binary(name) do
    name = String.trim(name)

    if String.length(name) in 1..100 and not Regex.match?(~r/[\x00-\x1f\x7f]/, name),
      do: {:ok, name},
      else: :error
  end

  defp name(_name, _host), do: :error

  defp json_type?(headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_, type} ->
        type = type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
        type == "application/json" or Regex.match?(~r{\Aapplication/[a-z0-9.-]+\+json\z}, type)

      nil ->
        false
    end
  end

  # The document's own cache lifetime, kept between five minutes and a day.
  defp refresh_at(headers) do
    directives =
      headers
      |> Enum.filter(fn {key, _} -> key == "cache-control" end)
      |> Enum.flat_map(fn {_, value} -> String.split(value, ",") end)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

    seconds =
      cond do
        "no-store" in directives or "no-cache" in directives ->
          @min_age

        max_age = Enum.find_value(directives, &max_age/1) ->
          max_age |> max(@min_age) |> min(@max_age)

        true ->
          @default_age
      end

    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  defp max_age("max-age=" <> value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds
      _ -> nil
    end
  end

  defp max_age(_directive), do: nil

  # No HTTP happens here: the document was read and checked before this
  # transaction. Two first reads of one address race on its primary key; the
  # second rolls back its client row and uses the first one's.
  defp save(url, attrs, refresh_at) do
    result =
      Repo.transaction(fn ->
        case Repo.one(from(d in Document, where: d.url == ^url, lock: "FOR UPDATE")) do
          %Document{client_id: id} = document ->
            client = Repo.get!(Client, id)
            client_attrs = RegentOAuth.Protocol.public_client(attrs.name, attrs.redirect_uris)

            case Boruta.Ecto.Admin.Clients.update_client(client, client_attrs) do
              {:ok, _client} -> :ok
              {:error, _changeset} -> Repo.rollback(:refused)
            end

            document |> Ecto.Changeset.change(refresh_at: refresh_at) |> Repo.update!()
            id

          nil ->
            client =
              case Boruta.Ecto.Admin.Clients.create_client(
                     RegentOAuth.Protocol.public_client(attrs.name, attrs.redirect_uris)
                   ) do
                {:ok, client} -> client
                {:error, _changeset} -> Repo.rollback(:refused)
              end

            now = DateTime.utc_now()

            row = %{
              url: url,
              client_id: client.id,
              refresh_at: refresh_at,
              inserted_at: now,
              updated_at: now
            }

            case Repo.insert_all(Document, [row], on_conflict: :nothing) do
              {1, _} -> client.id
              {0, _} -> Repo.rollback(:raced)
            end
        end
      end)

    case result do
      {:ok, id} ->
        # Boruta forgets the client inside the transaction too; a request
        # that read it again before the commit must not keep the old name.
        :ok = Boruta.Ecto.Clients.invalidate(%Boruta.Oauth.Client{id: id})
        {:ok, id}

      {:error, :raced} ->
        stored(url)

      {:error, _} ->
        :error
    end
  end

  # draft-ietf-oauth-client-id-metadata-document-02 section 3: HTTPS, a path,
  # no user, fragment, query or dot segments. Compared as the exact string.
  # Only the default port, so no address can probe another service on a host.
  defp client_id_url?(url) do
    with true <- address?(url) and RegentHttp.Public.valid_url?(url),
         %URI{path: path, query: nil, port: 443} when is_binary(path) and path not in ["", "/"] <-
           URI.parse(url) do
      not Enum.any?(String.split(path, "/"), &(&1 in [".", ".."]))
    else
      _ -> false
    end
  end
end
