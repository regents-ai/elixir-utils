defmodule RegentCacheTest do
  use ExUnit.Case, async: false

  alias RegentCache.Dragonfly

  @app :regent_cache_test

  setup do
    previous_enabled = Application.get_env(@app, :dragonfly_enabled)
    previous_name = Application.get_env(@app, :dragonfly_name)
    previous_module = Application.get_env(@app, :dragonfly_command_module)

    on_exit(fn ->
      restore(:dragonfly_enabled, previous_enabled)
      restore(:dragonfly_name, previous_name)
      restore(:dragonfly_command_module, previous_module)
      Process.delete(:dragonfly_commands)
      Process.delete(:dragonfly_values)
    end)
  end

  test "disabled cache computes from the canonical reader" do
    Application.put_env(@app, :dragonfly_enabled, false)

    assert {:ok, %{value: 1}} = RegentCache.fetch(@app, "subject:test", 15, value_fun(1))
  end

  test "reads valid dragonfly JSON" do
    configure_fake(%{"subject:test" => ~s({"value":2})})

    assert {:ok, %{value: 2}} = RegentCache.fetch(@app, "subject:test", 15, value_fun(1))
  end

  test "computes and stores after a miss" do
    configure_fake(%{})

    assert {:ok, %{value: 3}} = RegentCache.fetch(@app, "subject:test", 15, value_fun(3))

    assert [["GET", "subject:test"], ["SET", "subject:test", ~s({"value":3}), "EX", 15]] =
             Process.get(:dragonfly_commands)
  end

  test "bad cached JSON computes a fresh value" do
    configure_fake(%{"subject:test" => "not-json"})

    assert {:ok, %{value: 4}} = RegentCache.fetch(@app, "subject:test", 15, value_fun(4))
  end

  test "command errors compute a fresh value" do
    configure_fake(:error)

    assert {:ok, %{value: 5}} = RegentCache.fetch(@app, "subject:test", 15, value_fun(5))
  end

  test "status reports readiness" do
    configure_fake(%{})

    assert :ready = Dragonfly.status(@app)
  end

  defp value_fun(value), do: fn -> {:ok, %{value: value}} end

  defp configure_fake(values) do
    Application.put_env(@app, :dragonfly_enabled, true)
    Application.put_env(@app, :dragonfly_name, self())
    Application.put_env(@app, :dragonfly_command_module, __MODULE__.FakeRedix)
    Process.put(:dragonfly_values, values)
    Process.put(:dragonfly_commands, [])
  end

  defp restore(key, nil), do: Application.delete_env(@app, key)
  defp restore(key, value), do: Application.put_env(@app, key, value)

  defmodule FakeRedix do
    def command(owner, command) do
      send(owner, {:dragonfly_command, command})

      commands = Process.get(:dragonfly_commands, [])
      Process.put(:dragonfly_commands, commands ++ [command])

      case Process.get(:dragonfly_values) do
        :error ->
          {:error, :offline}

        values when is_map(values) ->
          run(command, values)
      end
    end

    defp run(["PING"], _values), do: {:ok, "PONG"}
    defp run(["GET", key], values), do: {:ok, Map.get(values, key)}
    defp run(["SET", _key, _value, "EX", _ttl], _values), do: {:ok, "OK"}
    defp run(["DEL" | _keys], _values), do: {:ok, 1}
  end
end
