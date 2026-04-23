defmodule RegentCache.Dragonfly do
  @moduledoc false

  require Logger

  @default_host "localhost"
  @default_port 6379

  @type app_name :: atom()

  @spec child_spec(app_name()) :: Supervisor.child_spec()
  def child_spec(app) when is_atom(app) do
    {Redix, name: redix_name(app), host: host(app), port: port(app)}
  end

  @spec enabled?(app_name()) :: boolean()
  def enabled?(app) when is_atom(app) do
    Application.get_env(app, :dragonfly_enabled, true) == true
  end

  @spec status(app_name()) :: :disabled | :ready | {:error, term()}
  def status(app) when is_atom(app) do
    if enabled?(app) do
      case command(app, ["PING"]) do
        {:ok, "PONG"} -> :ready
        {:ok, other} -> {:error, {:unexpected_ping, other}}
        {:error, reason} -> {:error, reason}
      end
    else
      :disabled
    end
  end

  @spec command(app_name(), [term()]) :: {:ok, term()} | {:error, term()}
  def command(app, command) when is_atom(app) and is_list(command) do
    if enabled?(app) do
      case redix_name(app) do
        nil ->
          {:error, :dragonfly_unavailable}

        name ->
          run_command(app, name, command)
      end
    else
      {:error, :dragonfly_disabled}
    end
  end

  def command(_app, _command), do: {:error, :invalid_command}

  @spec get(app_name(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get(app, key) when is_atom(app) and is_binary(key), do: command(app, ["GET", key])
  def get(_app, _key), do: {:error, :invalid_key}

  @spec set(app_name(), String.t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def set(app, key, value, ttl_seconds)
      when is_atom(app) and is_binary(key) and is_binary(value) and is_integer(ttl_seconds) and
             ttl_seconds > 0 do
    case command(app, ["SET", key, value, "EX", ttl_seconds]) do
      {:ok, "OK"} ->
        :ok

      {:ok, other} ->
        {:error, {:unexpected_set_result, other}}

      {:error, reason} ->
        Logger.debug("dragonfly set failed app=#{app} key=#{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def set(_app, _key, _value, _ttl_seconds), do: {:error, :invalid_set}

  @spec delete(app_name(), String.t() | [String.t()]) :: :ok | {:error, term()}
  def delete(app, keys) when is_atom(app) and is_list(keys) do
    keys = Enum.filter(keys, &is_binary/1)

    if keys == [] do
      :ok
    else
      case command(app, ["DEL" | keys]) do
        {:ok, _deleted} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def delete(app, key) when is_atom(app) and is_binary(key), do: delete(app, [key])
  def delete(_app, _key), do: {:error, :invalid_key}

  @spec redix_name(app_name()) :: atom() | pid() | nil
  defp redix_name(app), do: Application.get_env(app, :dragonfly_name, :dragonfly)

  defp host(app), do: Application.get_env(app, :dragonfly_host, @default_host)
  defp port(app), do: Application.get_env(app, :dragonfly_port, @default_port)

  defp command_module(app), do: Application.get_env(app, :dragonfly_command_module, Redix)

  defp run_command(app, name, command) do
    command_module(app).command(name, command)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
