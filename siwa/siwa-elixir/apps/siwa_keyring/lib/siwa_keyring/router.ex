defmodule SiwaKeyring.Router do
  use Plug.Router
  require Logger

  @max_body_bytes 65_536
  @read_length 8_192
  @read_timeout 5_000
  @parser_options Plug.Parsers.init(
                    parsers: [:json],
                    pass: ["application/json"],
                    json_decoder: Jason,
                    body_reader: {__MODULE__, :read_body, []},
                    length: @max_body_bytes,
                    read_length: @read_length,
                    read_timeout: @read_timeout
                  )

  plug(Plug.Logger)
  plug(:parse_body)
  plug(:match)
  plug(:authorize)
  plug(:dispatch)

  @prefix "/api/shared/keyring"

  def max_body_bytes, do: @max_body_bytes

  get @prefix <> "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  post @prefix <> "/create-wallet" do
    case run_keyring_request(:create_wallet, fn -> SiwaKeyring.create_wallet() end) do
      {:ok, wallet} -> send_json(conn, 200, wallet)
      {:error, _reason} -> send_error(conn, 422, "wallet_create_failed")
    end
  end

  post @prefix <> "/has-wallet" do
    case run_keyring_request(:has_wallet, fn -> SiwaKeyring.has_wallet?() end) do
      {:ok, result} -> send_json(conn, 200, result)
      {:error, _reason} -> send_error(conn, 422, "wallet_check_failed")
    end
  end

  post @prefix <> "/get-address" do
    case run_keyring_request(:get_address, fn -> SiwaKeyring.get_address() end) do
      {:ok, address} -> send_json(conn, 200, %{address: address})
      {:error, :wallet_missing} -> send_error(conn, 404, "wallet_not_found")
      {:error, _reason} -> send_error(conn, 422, "wallet_lookup_failed")
    end
  end

  post @prefix <> "/sign-message" do
    with {:ok, message} <- required_text(conn.body_params, "message", :message_required),
         {:ok, signature} <-
           run_keyring_request(:sign_message, fn -> SiwaKeyring.sign_message(message) end) do
      send_json(conn, 200, %{signature: signature})
    else
      {:error, :message_required} -> send_error(conn, 400, "message_required")
      {:error, _reason} -> send_error(conn, 422, "message_sign_failed")
    end
  end

  post @prefix <> "/sign-raw-message" do
    with {:ok, payload} <- required_text(conn.body_params, "payload", :payload_required),
         {:ok, signature} <-
           run_keyring_request(:sign_raw_message, fn -> SiwaKeyring.sign_raw_message(payload) end) do
      send_json(conn, 200, %{signature: signature})
    else
      {:error, :payload_required} -> send_error(conn, 400, "payload_required")
      {:error, _reason} -> send_error(conn, 422, "raw_message_sign_failed")
    end
  end

  post @prefix <> "/sign-transaction" do
    with {:ok, transaction} <-
           required_wallet_action(conn.body_params, "transaction", :transaction_required),
         {:ok, signed} <-
           run_keyring_request(:sign_transaction, fn ->
             SiwaKeyring.sign_transaction(transaction)
           end) do
      send_json(conn, 200, signed)
    else
      {:error, :transaction_required} -> send_error(conn, 400, "transaction_required")
      {:error, _reason} -> send_error(conn, 422, "transaction_sign_failed")
    end
  end

  post @prefix <> "/sign-authorization" do
    with {:ok, authorization} <-
           required_wallet_action(conn.body_params, "authorization", :authorization_required),
         {:ok, signed} <-
           run_keyring_request(:sign_authorization, fn ->
             SiwaKeyring.sign_authorization(authorization)
           end) do
      send_json(conn, 200, signed)
    else
      {:error, :authorization_required} -> send_error(conn, 400, "authorization_required")
      {:error, _reason} -> send_error(conn, 422, "authorization_sign_failed")
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp authorize(%Plug.Conn{request_path: "/api/shared/keyring/health"} = conn, _opts), do: conn

  defp authorize(conn, _opts) do
    secret = Application.fetch_env!(:siwa_keyring, :secret)
    body = request_body(conn)
    request_id = header(conn, "x-keyring-request-id")
    timestamp = header(conn, "x-keyring-timestamp")

    case authorize_once(secret, conn, body, request_id, timestamp) do
      :ok ->
        conn

      {:error, reason} ->
        Logger.warning("keyring request authorization failed: #{inspect(reason)}")
        conn |> send_error(401, "unauthorized") |> halt()
    end
  end

  defp authorize_once(secret, conn, body, request_id, timestamp) do
    with :ok <-
           SiwaKeyring.Auth.verify_hmac(
             secret,
             conn.method,
             conn.request_path,
             body,
             request_id,
             timestamp,
             header(conn, "x-keyring-signature")
           ),
         {:ok, expires_at_ms} <- SiwaKeyring.Auth.request_expires_at_ms(timestamp),
         :ok <- SiwaKeyring.ReplayStore.consume(request_id, expires_at_ms) do
      :ok
    end
  end

  defp request_body(conn) do
    case conn.private[:raw_body] do
      body when is_binary(body) ->
        body

      _ ->
        encoded_body_params(conn)
    end
  end

  defp encoded_body_params(conn) do
    content_type = Plug.Conn.get_req_header(conn, "content-type")

    case {content_type, conn.body_params} do
      {[], _params} -> ""
      {_content_type, %Plug.Conn.Unfetched{}} -> ""
      {_content_type, params} when is_map(params) -> Jason.encode!(params)
      {_content_type, _params} -> ""
    end
  end

  defp header(conn, key), do: Plug.Conn.get_req_header(conn, key) |> List.first() |> to_string()

  defp parse_body(conn, _opts) do
    Plug.Parsers.call(conn, @parser_options)
  rescue
    exception in Plug.Parsers.RequestTooLargeError ->
      Logger.warning("keyring request body too large: #{Exception.message(exception)}")
      conn |> send_error(413, "request_body_too_large") |> halt()

    exception in Plug.Parsers.ParseError ->
      Logger.warning("keyring request body malformed: #{Exception.message(exception)}")
      conn |> send_error(400, "malformed_json") |> halt()

    exception in Plug.Parsers.BadEncodingError ->
      Logger.warning("keyring request body encoding invalid: #{Exception.message(exception)}")
      conn |> send_error(400, "malformed_json") |> halt()

    exception in Plug.Parsers.UnsupportedMediaTypeError ->
      Logger.warning("keyring request content type unsupported: #{Exception.message(exception)}")
      conn |> send_error(415, "unsupported_media_type") |> halt()

    exception in Plug.BadRequestError ->
      Logger.warning("keyring request body invalid: #{Exception.message(exception)}")
      conn |> send_error(400, "bad_request") |> halt()
  end

  def read_body(conn, opts) do
    opts = bounded_read_opts(opts)
    previous = conn.private[:raw_body] || ""

    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        full_body = previous <> body
        conn = Plug.Conn.put_private(conn, :raw_body, full_body)

        if byte_size(full_body) > @max_body_bytes do
          {:more, body, conn}
        else
          {:ok, body, conn}
        end

      {:more, body, conn} ->
        full_body = previous <> body
        {:more, body, Plug.Conn.put_private(conn, :raw_body, full_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bounded_read_opts(opts) do
    opts
    |> Keyword.put(:length, bounded_integer(opts[:length], @max_body_bytes))
    |> Keyword.put(:read_length, bounded_integer(opts[:read_length], @read_length))
    |> Keyword.put_new(:read_timeout, @read_timeout)
  end

  defp bounded_integer(value, max) when is_integer(value) and value > 0, do: min(value, max)
  defp bounded_integer(_value, max), do: max

  defp send_json(conn, status, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(payload))
  end

  defp required_text(params, key, error_code) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, error_code}
          _trimmed -> {:ok, value}
        end

      _value ->
        {:error, error_code}
    end
  end

  defp required_wallet_action(params, key, error_code) do
    case Map.get(params, key) do
      value when is_map(value) ->
        case Siwa.WalletAction.validate(value) do
          {:ok, action} -> {:ok, action}
          {:error, _reason} -> {:error, error_code}
        end

      _value ->
        {:error, error_code}
    end
  end

  defp run_keyring_request(action, fun) do
    fun.()
  rescue
    _error ->
      Logger.error("keyring #{action} crashed")

      {:error, :internal_failure}
  catch
    _kind, _reason ->
      Logger.error("keyring #{action} exited")
      {:error, :internal_failure}
  else
    {:ok, result} ->
      {:ok, result}

    {:error, reason} = error ->
      Logger.warning("keyring #{action} failed: #{redacted_reason(reason)}")
      error

    other ->
      Logger.error("keyring #{action} returned an unexpected response: #{redacted_reason(other)}")
      {:error, :internal_failure}
  end

  defp redacted_reason(reason) when reason in [:wallet_missing, :wallet_already_exists],
    do: Atom.to_string(reason)

  defp redacted_reason(_reason), do: "redacted"

  defp send_error(conn, status, error) do
    send_json(conn, status, %{error: error})
  end
end
