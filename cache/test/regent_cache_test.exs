defmodule RegentCacheTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  @cache :regent_cache_test_cache

  setup do
    start_supervised!({Cachex, name: @cache})
    {:ok, _count} = Cachex.clear(@cache)
    :ok
  end

  test "reads valid JSON with string keys" do
    assert :ok = RegentCache.put_json(@cache, "subject:test", %{"value" => 2}, 15)

    assert {:ok, %{"value" => 2}} = RegentCache.fetch(@cache, "subject:test", 15, value_fun(1))
  end

  test "computes and stores after a miss" do
    assert {:ok, %{value: 3}} = RegentCache.fetch(@cache, "subject:test", 15, value_fun(3))

    assert {:ok, %{"value" => 3}} = RegentCache.get_json(@cache, "subject:test")
  end

  test "bad cached JSON computes a fresh value" do
    assert {:ok, true} = Cachex.put(@cache, "subject:test", "not-json", ttl: :timer.seconds(15))

    assert {:ok, %{value: 4}} = RegentCache.fetch(@cache, "subject:test", 15, value_fun(4))
  end

  test "bad cached JSON reads as a decode failure, not a miss" do
    assert {:ok, true} = Cachex.put(@cache, "subject:test", "not-json", ttl: :timer.seconds(15))

    assert {:error, {:decode_failure, %Jason.DecodeError{}}} =
             RegentCache.get_json(@cache, "subject:test")
  end

  test "delete removes keys and ignores non-binary entries" do
    assert :ok = RegentCache.put_json(@cache, "subject:a", %{"value" => 1}, 15)
    assert :ok = RegentCache.put_json(@cache, "subject:b", %{"value" => 2}, 15)

    assert :ok = RegentCache.delete(@cache, ["subject:a", :not_a_key, "subject:b"])

    assert :miss = RegentCache.get_json(@cache, "subject:a")
    assert :miss = RegentCache.get_json(@cache, "subject:b")
  end

  test "delete reports failures instead of swallowing them" do
    assert {:error, _reason} = RegentCache.delete(:missing_cache, ["subject:test"])
  end

  test "loader errors are not cached" do
    assert {:error, :boom} =
             RegentCache.fetch(@cache, "subject:test", 15, fn -> {:error, :boom} end)

    assert :miss = RegentCache.get_json(@cache, "subject:test")

    assert {:ok, %{value: 6}} = RegentCache.fetch(@cache, "subject:test", 15, value_fun(6))
  end

  test "cache errors compute a fresh value" do
    assert {:ok, %{value: 5}} =
             RegentCache.fetch(:missing_cache, "subject:test", 15, value_fun(5))
  end

  test "write-back failure warns but still returns the fresh value" do
    # Loader runs after the (successful) cache read returned :miss, then takes
    # the cache down so the write-back fails while the fresh value is returned.
    loader = fn ->
      :ok = stop_supervised(Cachex)
      {:ok, %{value: 7}}
    end

    log =
      capture_log([level: :warning], fn ->
        assert {:ok, %{value: 7}} = RegentCache.fetch(@cache, "subject:test", 15, loader)
      end)

    assert log =~ "cache write-back failed"
    assert log =~ "key_hash=#{RegentCache.digest("subject:test")}"
    refute log =~ "subject:test\""
  end

  test "cache write failures do not log raw keys" do
    sensitive_key = "siwa:request:v1:0xabc0000000000000000000000000000000000001:rate"

    log =
      capture_log([level: :debug], fn ->
        assert {:error, _reason} = RegentCache.put_json(:missing_cache, sensitive_key, %{}, 15)
      end)

    assert log =~ "key_hash=#{RegentCache.digest(sensitive_key)}"
    refute log =~ sensitive_key
    refute log =~ "0xabc0000000000000000000000000000000000001"
  end

  test "status reports readiness" do
    assert :ready = RegentCache.status(@cache)
  end

  test "set helpers use local cache state" do
    assert :ok = RegentCache.set_add(@cache, "watch:online:1", "sess-1", 15)
    assert :ok = RegentCache.set_add(@cache, "watch:online:1", "sess-2", 15)
    assert {:ok, ["sess-1", "sess-2"]} = RegentCache.set_members(@cache, "watch:online:1")
    assert :ok = RegentCache.set_remove(@cache, "watch:online:1", "sess-1", 15)
    assert {:ok, ["sess-2"]} = RegentCache.set_members(@cache, "watch:online:1")
  end

  test "counter helpers increment string values" do
    assert {:ok, 1} = RegentCache.increment(@cache, "subject:epoch", 15)
    assert {:ok, "1"} = RegentCache.get_string(@cache, "subject:epoch")
    assert {:ok, 2} = RegentCache.increment(@cache, "subject:epoch", 15)
  end

  defp value_fun(value), do: fn -> {:ok, %{value: value}} end
end
