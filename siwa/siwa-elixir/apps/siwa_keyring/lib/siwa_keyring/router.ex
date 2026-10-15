defmodule SiwaKeyring.Router do
  use Plug.Router
  require Logger

  @max_body_bytes 65_536
  @read_length 8_192
  @read_timeout 5_000
  @boundary_error :keyring_boundary_failure
  @file_io_errors [
    :eacces,
    :eagain,
    :ebadf,
    :edeadlk,
    :edquot,
    :eexist,
    :efault,
    :efbig,
    :eintr,
    :einval,
    :eio,
    :eisdir,
    :eloop,
    :emfile,
    :emlink,
    :enametoolong,
    :enfile,
    :enobufs,
    :enodev,
    :enoent,
    :enomem,
    :enospc,
    :enotblk,
    :enotdir,
    :enotsup,
    :enxio,
    :eperm,
    :epipe,
    :erofs,
    :espipe,
    :esrch,
    :estale,
    :exdev
  ]
  @crypto_errors [
    :invalid_hex,
    :invalid_message,
    :invalid_payload,
    :invalid_public_key,
    :invalid_recovery_id,
    :invalid_signature,
    :invalid_signature_encoding,
    :missing_public_key
  ]
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
    keyring = keyring_module()

    case run_keyring_request(:create_wallet, fn -> keyring.create_wallet() end) do
      {:ok, wallet} -> send_json(conn, 200, wallet)
      {:error, reason} -> send_keyring_error(conn, reason, 422, "wallet_create_failed")
    end
  end

  post @prefix <> "/has-wallet" do
    keyring = keyring_module()

    case run_keyring_request(:has_wallet, fn -> keyring.has_wallet?() end) do
      {:ok, result} -> send_json(conn, 200, result)
      {:error, reason} -> send_keyring_error(conn, reason, 422, "wallet_check_failed")
    end
  end

  post @prefix <> "/get-address" do
    keyring = keyring_module()

    case run_keyring_request(:get_address, fn -> keyring.get_address() end) do
      {:ok, address} -> send_json(conn, 200, %{address: address})
      {:error, :wallet_missing} -> send_error(conn, 404, "wallet_not_found")
      {:error, reason} -> send_keyring_error(conn, reason, 422, "wallet_lookup_failed")
    end
  end

  post @prefix <> "/sign-message" do
    keyring = keyring_module()

    with {:ok, message} <- required_text(conn.body_params, "message", :message_required),
         {:ok, signature} <-
           run_keyring_request(:sign_message, fn -> keyring.sign_message(message) end) do
      send_json(conn, 200, %{signature: signature})
    else
      {:error, :message_required} -> send_error(conn, 400, "message_required")
      {:error, reason} -> send_keyring_error(conn, reason, 422, "message_sign_failed")
    end
  end

  post @prefix <> "/sign-raw-message" do
    keyring = keyring_module()

    with {:ok, payload} <- required_text(conn.body_params, "payload", :payload_required),
         {:ok, signature} <-
           run_keyring_request(:sign_raw_message, fn -> keyring.sign_raw_message(payload) end) do
      send_json(conn, 200, %{signature: signature})
    else
      {:error, :payload_required} -> send_error(conn, 400, "payload_required")
      {:error, reason} -> send_keyring_error(conn, reason, 422, "raw_message_sign_failed")
    end
  end

  post @prefix <> "/sign-transaction" do
    keyring = keyring_module()

    with {:ok, transaction} <-
           required_wallet_action(conn.body_params, "transaction", :transaction_required),
         {:ok, signed} <-
           run_keyring_request(:sign_transaction, fn ->
             keyring.sign_transaction(transaction)
           end) do
      send_json(conn, 200, signed)
    else
      {:error, :transaction_required} -> send_error(conn, 400, "transaction_required")
      {:error, reason} -> send_keyring_error(conn, reason, 422, "transaction_sign_failed")
    end
  end

  post @prefix <> "/sign-authorization" do
    keyring = keyring_module()

    with {:ok, authorization} <-
           required_wallet_action(conn.body_params, "authorization", :authorization_required),
         {:ok, signed} <-
           run_keyring_request(:sign_authorization, fn ->
             keyring.sign_authorization(authorization)
           end) do
      send_json(conn, 200, signed)
    else
      {:error, :authorization_required} -> send_error(conn, 400, "authorization_required")
      {:error, reason} -> send_keyring_error(conn, reason, 422, "authorization_sign_failed")
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
    result = fun.()

    handle_keyring_result(action, result)
  rescue
    exception ->
      keyring_unexpected_exception(action, exception)
  catch
    :throw, reason ->
      keyring_unexpected_control_flow(action, "throw", reason)

    :exit, reason ->
      keyring_unexpected_control_flow(action, "exit", reason)

    kind, reason ->
      keyring_unexpected_control_flow(action, Atom.to_string(kind), reason)
  end

  defp handle_keyring_result(action, result) do
    case result do
      {:ok, _result} = ok ->
        ok

      {:error, reason} = error ->
        case expected_keyring_error_class(reason) do
          {:ok, error_class} ->
            log_keyring_failure(:warning, action, error_class, redacted_reason(reason))
            error

          :error ->
            log_keyring_failure(:error, action, "unexpected_error", "redacted")
            {:error, @boundary_error}
        end

      other ->
        log_keyring_failure(:error, action, "unexpected_return", redacted_reason(other))
        {:error, @boundary_error}
    end
  end

  defp keyring_unexpected_exception(action, exception) do
    error_class = exception.__struct__ |> Module.split() |> List.last()

    log_keyring_failure(
      :error,
      action,
      error_class,
      sanitized_exception_message(exception)
    )

    {:error, @boundary_error}
  end

  defp keyring_unexpected_control_flow(action, error_class, _reason) do
    log_keyring_failure(:error, action, error_class, "redacted")
    {:error, @boundary_error}
  end

  defp expected_keyring_error_class(:wallet_missing), do: {:ok, "wallet_missing"}
  defp expected_keyring_error_class(:wallet_already_exists), do: {:ok, "wallet_already_exists"}

  defp expected_keyring_error_class(:keystore_decrypt_failed),
    do: {:ok, "keystore_decrypt_failed"}

  defp expected_keyring_error_class(:invalid_wallet_action), do: {:ok, "invalid_params"}
  defp expected_keyring_error_class(:unexpected_signer), do: {:ok, "invalid_params"}

  defp expected_keyring_error_class(reason) when reason in @file_io_errors,
    do: {:ok, "file_io_error"}

  defp expected_keyring_error_class(reason) when reason in @crypto_errors,
    do: {:ok, "crypto_error"}

  defp expected_keyring_error_class(_reason), do: :error

  defp sanitized_exception_message(_exception), do: "redacted"

  defp send_keyring_error(conn, @boundary_error, _status, _error) do
    send_error(conn, 500, "keyring_request_failed")
  end

  defp send_keyring_error(conn, _reason, status, error) do
    send_error(conn, status, error)
  end

  defp log_keyring_failure(level, action, error_class, reason) do
    :telemetry.execute(
      [:siwa_keyring, :router, :keyring_request, :failure],
      %{count: 1},
      %{action: action, error_class: error_class}
    )

    Logger.log(
      level,
      "keyring request failed action=#{action} error_class=#{error_class} reason=#{reason}"
    )
  end

  defp keyring_module do
    Application.get_env(:siwa_keyring, :router_keyring_module, SiwaKeyring)
  end

  defp redacted_reason(reason) when reason in [:wallet_missing, :wallet_already_exists],
    do: Atom.to_string(reason)

  defp redacted_reason(_reason), do: "redacted"

  defp send_error(conn, status, error) do
    send_json(conn, status, %{error: error})
  end
end
