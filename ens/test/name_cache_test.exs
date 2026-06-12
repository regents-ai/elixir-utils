defmodule AgentEns.NameCacheTest do
  use ExUnit.Case, async: true

  alias AgentEns.NameCache

  @wallet "0x1234567890abcdef1234567890abcdef12345678"
  @other_wallet "0x9999999999999999999999999999999999999999"
  @rpc_url "https://rpc.test.invalid"

  defmodule CacheStub do
    def get_json(cache, key) do
      case Map.fetch(state(cache), key) do
        {:ok, {value, _ttl}} -> {:ok, value}
        :error -> :miss
      end
    end

    def put_json(cache, key, value, ttl_seconds) do
      put_state(cache, Map.put(state(cache), key, {value, ttl_seconds}))
      :ok
    end

    def state(cache) do
      Agent.get(cache, & &1)
    end

    def ttl(cache, key) do
      case Map.fetch(state(cache), key) do
        {:ok, {_value, ttl}} -> ttl
        :error -> nil
      end
    end

    defp put_state(cache, state), do: Agent.update(cache, fn _ -> state end)
  end

  defp start_cache(context) do
    name = :"name_cache_test_#{context.test |> :erlang.phash2()}"
    start_supervised!(%{id: name, start: {Agent, :start_link, [fn -> %{} end, [name: name]]}})
    %{cache: name}
  end

  setup :start_cache

  defp opts(cache, resolver) do
    [
      cache: cache,
      cache_module: CacheStub,
      rpc_url: @rpc_url,
      resolver: resolver
    ]
  end

  test "resolves, caches, and serves repeat lookups from the cache", %{cache: cache} do
    counter = :counters.new(1, [])

    resolver = fn @wallet, _opts ->
      :counters.add(counter, 1, 1)
      {:ok, "alice.eth"}
    end

    assert NameCache.resolve(@wallet, opts(cache, resolver)) == "alice.eth"
    assert NameCache.resolve(@wallet, opts(cache, resolver)) == "alice.eth"
    assert :counters.get(counter, 1) == 1
    assert CacheStub.ttl(cache, "ens:primary-name:" <> @wallet) == 6 * 60 * 60
  end

  test "normalizes wallets before lookup and returns nil for invalid input", %{cache: cache} do
    resolver = fn @wallet, _opts -> {:ok, "alice.eth"} end

    upper = "0x" <> String.upcase(String.trim_leading(@wallet, "0x"))
    assert NameCache.resolve(upper, opts(cache, resolver)) == "alice.eth"
    assert NameCache.resolve("not-a-wallet", opts(cache, resolver)) == nil
    assert NameCache.resolve(nil, opts(cache, resolver)) == nil
  end

  test "negative-caches wallets without a verified name", %{cache: cache} do
    resolver = fn _wallet, _opts -> {:ok, nil} end

    assert NameCache.resolve(@wallet, opts(cache, resolver)) == nil
    assert CacheStub.ttl(cache, "ens:primary-name:" <> @wallet) == 15 * 60
  end

  test "caches resolver failures briefly and returns nil", %{cache: cache} do
    resolver = fn _wallet, _opts -> {:error, :rpc_down} end

    assert NameCache.resolve(@wallet, opts(cache, resolver)) == nil
    assert CacheStub.ttl(cache, "ens:primary-name:" <> @wallet) == 60
  end

  test "returns nil without caching when rpc_url is blank", %{cache: cache} do
    resolver = fn _wallet, _opts -> flunk("resolver must not run without an rpc url") end

    assert NameCache.resolve(@wallet, Keyword.put(opts(cache, resolver), :rpc_url, "")) == nil
    assert NameCache.resolve(@wallet, Keyword.delete(opts(cache, resolver), :rpc_url)) == nil
    assert CacheStub.state(cache) == %{}
  end

  test "works without any cache configured" do
    resolver = fn @wallet, _opts -> {:ok, "alice.eth"} end

    assert NameCache.resolve(@wallet, rpc_url: @rpc_url, resolver: resolver) == "alice.eth"
  end

  test "resolve_many mixes cache hits and concurrent misses", %{cache: cache} do
    resolver = fn
      @wallet, _opts -> {:ok, "alice.eth"}
      @other_wallet, _opts -> {:ok, nil}
    end

    assert NameCache.resolve(@wallet, opts(cache, resolver)) == "alice.eth"

    only_misses_resolver = fn
      @other_wallet, _opts -> {:ok, nil}
      wallet, _opts -> flunk("unexpected resolver call for cached wallet #{wallet}")
    end

    assert NameCache.resolve_many(
             [@wallet, @other_wallet, "junk", nil, @wallet],
             opts(cache, only_misses_resolver)
           ) == %{@wallet => "alice.eth", @other_wallet => nil}
  end

  test "resolve_many survives resolver timeouts with nil entries", %{cache: cache} do
    resolver = fn _wallet, _opts ->
      Process.sleep(:infinity)
    end

    assert NameCache.resolve_many(
             [@wallet],
             Keyword.put(opts(cache, resolver), :timeout_ms, 50)
           ) == %{@wallet => nil}

    assert CacheStub.state(cache) == %{}
  end
end
