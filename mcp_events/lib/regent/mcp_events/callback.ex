defmodule Regent.MCPEvents.Callback do
  @moduledoc """
  HTTPS callbacks with connection-time DNS checks and a pinned destination IP.

  Mint connects directly to the validated IP tuple while the original hostname
  remains the HTTP Host, TLS SNI and certificate verification name. Each call
  opens a new connection; there are no proxies, redirects, pools or hidden retries.
  """

  @timeout_ms 10_000
  @response_limit 16_384
  @ipv4_denied [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 88, 99, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @doc "Checks callback URL syntax, including non-public literal addresses."
  def validate(url) when is_binary(url) and byte_size(url) in 1..8192 do
    with {:ok, uri} <- URI.new(url),
         true <- uri.scheme == "https" and is_binary(uri.host) and uri.host != "",
         true <- is_nil(uri.userinfo) and is_nil(uri.fragment),
         true <- is_integer(uri.port) and uri.port in 1..65_535,
         true <- valid_host?(uri.host),
         true <- not Regex.match?(~r/[\x00-\x20\x7f\\]/, url) do
      {:ok, uri}
    else
      _ -> {:error, :invalid_callback}
    end
  end

  def validate(_), do: {:error, :invalid_callback}

  @doc "Returns whether an IP tuple is globally routable; transition and mapped IPv6 are rejected."
  def public_ip?({a, b, c, d} = ip)
      when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 do
    ip != {168, 63, 129, 16} and
      not Enum.any?(@ipv4_denied, fn {network, bits} -> in_network?(ip, network, bits) end)
  end

  def public_ip?({a, b, c, d, e, f, g, h})
      when a in 0..65_535 and b in 0..65_535 and c in 0..65_535 and d in 0..65_535 and
             e in 0..65_535 and f in 0..65_535 and g in 0..65_535 and h in 0..65_535 do
    # Only global unicast. Exclude IANA protocol space, documentation and 6to4.
    a in 0x2000..0x3FFF and not (a == 0x2001 and b < 0x0200) and
      not (a == 0x2001 and b == 0x0DB8) and a != 0x2002 and
      not (a == 0x3FFF and b < 0x1000)
  end

  def public_ip?(_), do: false

  @doc "Posts exact signed bytes with a total bounded network deadline."
  def post(url, body, headers), do: do_post(url, body, headers, :verification)

  @doc "Posts one event; a complete HTTP response header acknowledges receipt without waiting for a body."
  def post_event(url, body, headers), do: do_post(url, body, headers, :event)

  defp do_post(url, body, headers, mode) when is_binary(body) and byte_size(body) <= 262_144 do
    deadline = System.monotonic_time(:millisecond) + @timeout_ms

    with {:ok, uri} <- validate(url),
         {:ok, address} <- resolve(uri.host, deadline),
         {:ok, conn} <- connect(uri, address, deadline) do
      try do
        request(conn, uri, body, headers, deadline, mode)
      after
        Mint.HTTP.close(conn)
      end
    end
  end

  defp do_post(_, _, _, _), do: {:error, :payload_too_large}

  defp valid_host?(host) do
    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, address} ->
        public_ip?(address)

      {:error, _} ->
        byte_size(host) <= 253 and
          Regex.match?(~r/\A[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z/, host) and
          Enum.all?(String.split(host, "."), fn label ->
            byte_size(label) in 1..63 and not String.starts_with?(label, "-") and
              not String.ends_with?(label, "-")
          end)
    end
  end

  defp resolve(host, deadline) do
    host = String.to_charlist(host)

    case :inet.parse_strict_address(host) do
      {:ok, ip} -> if public_ip?(ip), do: {:ok, ip}, else: {:error, :non_public_callback}
      {:error, _} -> resolve_name(host, deadline)
    end
  end

  defp resolve_name(host, deadline) do
    # Validate every answer, not merely whichever address is selected first.
    answers =
      for family <- [:inet, :inet6] do
        :inet.getaddrs(host, family, remaining(deadline))
      end

    addresses = for {:ok, ips} <- answers, ip <- ips, do: ip

    cond do
      System.monotonic_time(:millisecond) >= deadline -> {:error, :timeout}
      Enum.any?(answers, &(&1 == {:error, :timeout})) -> {:error, :timeout}
      addresses == [] -> {:error, :dns_error}
      not Enum.all?(addresses, &public_ip?/1) -> {:error, :non_public_callback}
      true -> {:ok, hd(addresses)}
    end
  end

  defp connect(uri, address, deadline) do
    ipv6? = tuple_size(address) == 8

    case Mint.HTTP.connect(:https, address, uri.port,
           hostname: uri.host,
           protocols: [:http1],
           mode: :passive,
           max_header_list_size: @response_limit,
           transport_opts: [
             timeout: remaining(deadline),
             send_timeout: remaining(deadline),
             send_timeout_close: true,
             inet4: not ipv6?,
             inet6: ipv6?,
             cacerts: :public_key.cacerts_get()
           ]
         ) do
      {:ok, conn} -> {:ok, conn}
      {:error, error} -> {:error, network_reason(error)}
    end
  end

  defp request(conn, uri, body, headers, deadline, mode) do
    path = if uri.path in [nil, ""], do: "/", else: uri.path
    path = if is_nil(uri.query), do: path, else: path <> "?" <> uri.query
    host = if String.contains?(uri.host, ":"), do: "[#{uri.host}]", else: uri.host
    host = if uri.port == 443, do: host, else: host <> ":" <> Integer.to_string(uri.port)

    headers = [
      {"host", host} | Enum.reject(headers, fn {key, _} -> String.downcase(key) == "host" end)
    ]

    case Mint.HTTP.request(conn, "POST", path, headers, body) do
      {:ok, conn, ref} ->
        response = %{status: nil, body: if(mode == :event, do: nil, else: "")}
        receive_response(conn, ref, deadline, response)

      {:error, _conn, error} ->
        {:error, network_reason(error)}
    end
  end

  defp receive_response(conn, ref, deadline, response) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      case Mint.HTTP.recv(conn, 0, remaining(deadline)) do
        {:ok, conn, messages} -> consume(messages, conn, ref, deadline, response)
        {:error, _conn, error, _messages} -> {:error, network_reason(error)}
      end
    end
  end

  defp consume([], conn, ref, deadline, response),
    do: receive_response(conn, ref, deadline, response)

  defp consume([{:status, ref, status} | rest], conn, ref, deadline, response) do
    if status >= 300 do
      {:ok, %{response | status: status}}
    else
      consume(rest, conn, ref, deadline, %{response | status: status})
    end
  end

  defp consume([{:data, ref, chunk} | rest], conn, ref, deadline, response) do
    if byte_size(response.body) + byte_size(chunk) <= @response_limit do
      consume(rest, conn, ref, deadline, %{response | body: response.body <> chunk})
    else
      {:error, :response_too_large}
    end
  end

  defp consume(
         [{:headers, ref, _headers} | _],
         _conn,
         ref,
         _deadline,
         %{body: nil, status: status} = response
       )
       when status in 200..299,
       do: {:ok, response}

  defp consume([{:done, ref} | _], _conn, ref, _deadline, response), do: {:ok, response}

  defp consume([{:error, ref, error} | _], _conn, ref, _deadline, _response),
    do: {:error, network_reason(error)}

  defp consume([_ | rest], conn, ref, deadline, response),
    do: consume(rest, conn, ref, deadline, response)

  defp remaining(deadline), do: max(1, deadline - System.monotonic_time(:millisecond))

  defp network_reason(%Mint.TransportError{reason: :timeout}), do: :timeout
  defp network_reason(%Mint.TransportError{reason: {:tls_alert, _}}), do: :tls_error
  defp network_reason(_), do: :connection_error

  defp in_network?(ip, network, bits) do
    shift = 32 - bits
    Bitwise.bsr(ip_number(ip), shift) == Bitwise.bsr(ip_number(network), shift)
  end

  defp ip_number({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d
end
