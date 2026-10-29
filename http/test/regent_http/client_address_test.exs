defmodule RegentHttp.ClientAddressTest do
  use ExUnit.Case, async: false

  alias RegentHttp.ClientAddress

  setup do
    on_exit(fn -> Application.delete_env(:regent_http, :behind_fly_proxy) end)
  end

  defp conn(remote_ip, headers \\ []) do
    conn = %{Plug.Test.conn(:get, "/") | remote_ip: remote_ip}

    Enum.reduce(headers, conn, fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
  end

  describe "behind Fly's proxy" do
    setup do: Application.put_env(:regent_http, :behind_fly_proxy, true)

    test "keys the one Fly-Client-IP and never X-Forwarded-For" do
      conn =
        conn({10, 0, 0, 1}, [
          {"fly-client-ip", "203.0.113.7"},
          {"x-forwarded-for", "198.51.100.1"}
        ])

      assert ClientAddress.key(conn) == {{203, 0, 113, 7}, :client_header}
    end

    test "without one parseable Fly-Client-IP, the proxy's peer bucket" do
      assert ClientAddress.key(conn({10, 0, 0, 1})) == {{10, 0, 0, 1}, :peer_fallback}

      assert ClientAddress.key(conn({10, 0, 0, 1}, [{"fly-client-ip", "not an address"}])) ==
               {{10, 0, 0, 1}, :peer_fallback}

      assert ClientAddress.key(conn({10, 0, 0, 1}, [{"x-forwarded-for", "198.51.100.1"}])) ==
               {{10, 0, 0, 1}, :peer_fallback}
    end

    test "an IPv6 client shares its /64, and a mapped IPv4 address its IPv4 bucket" do
      assert ClientAddress.key(conn({10, 0, 0, 1}, [{"fly-client-ip", "2001:db8:1:2:3:4:5:6"}])) ==
               {{0x2001, 0xDB8, 1, 2, 0, 0, 0, 0}, :client_header}

      assert ClientAddress.key(conn({10, 0, 0, 1}, [{"fly-client-ip", "::ffff:203.0.113.7"}])) ==
               {{203, 0, 113, 7}, :client_header}
    end
  end

  describe "anywhere else" do
    setup do: Application.put_env(:regent_http, :behind_fly_proxy, false)

    test "the direct peer decides and no header is read" do
      conn = conn({127, 0, 0, 1}, [{"fly-client-ip", "203.0.113.7"}])
      assert ClientAddress.key(conn) == {{127, 0, 0, 1}, :peer}
    end
  end
end
