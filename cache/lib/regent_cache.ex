defmodule RegentCache do
  @moduledoc """
  Shared Cachex-backed cache helpers for Regent Elixir applications.
  """

  require Logger

  @type cache_name :: atom()

  @spec child_spec(cache_name()) :: Supervisor.child_spec()
  def child_spec(cache_name) when is_atom(cache_name), do: {Cachex, name: cache_name}

  @spec status(cache_name()) :: :ready | {:error, term()}
  def status(cache_name) when is_atom(cache_name) do
    case Cachex.exists?(cache_name, "__regent_cache_health__") do
      {:ok, _exists?} -> :ready
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec fetch(cache_name(), String.t(), pos_integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def fetch(cache_name, key, ttl_seconds, fun)
      when is_atom(cache_name) and is_binary(key) and is_integer(ttl_seconds) and
             ttl_seconds > 0 and is_function(fun, 0) do
    case get_json(cache_name, key) do
      {:ok, value} ->
        {:ok, value}

      :miss ->
        with {:ok, value} <- fun.() do
          _ = put_json(cache_name, key, value, ttl_seconds)
          {:ok, value}
        end

      {:error, _reason} ->
        fun.()
    end
  end

  @spec get_json(cache_name(), String.t()) :: {:ok, term()} | :miss | {:error, term()}
  def get_json(cache_name, key) when is_atom(cache_name) and is_binary(key) do
    case Cachex.get(cache_name, key) do
      {:ok, nil} ->
        :miss

      {:ok, value} when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, reason}
        end

      {:ok, _value} ->
        {:error, :invalid_cached_value}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec put_json(cache_name(), String.t(), term(), pos_integer()) :: :ok | {:error, term()}
  def put_json(cache_name, key, value, ttl_seconds)
      when is_atom(cache_name) and is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    with {:ok, encoded} <- Jason.encode(value) do
      case Cachex.put(cache_name, key, encoded, ttl: :timer.seconds(ttl_seconds)) do
        {:ok, true} -> :ok
        {:ok, other} -> {:error, {:unexpected_put_result, other}}
        {:error, reason} -> log_put_error(cache_name, key, reason)
      end
    end
  rescue
    error ->
      log_put_error(cache_name, key, error)
  catch
    :exit, reason ->
      log_put_error(cache_name, key, reason)
  end

  @spec delete(cache_name(), String.t() | [String.t()]) :: :ok | {:error, term()}
  def delete(cache_name, keys) when is_atom(cache_name) and is_list(keys) do
    keys = Enum.filter(keys, &is_binary/1)

    Enum.each(keys, fn key -> Cachex.del(cache_name, key) end)
    :ok
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  def delete(cache_name, key) when is_atom(cache_name) and is_binary(key),
    do: delete(cache_name, [key])

  def delete(_cache_name, _keys), do: {:error, :invalid_key}

  @spec get_string(cache_name(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_string(cache_name, key) when is_atom(cache_name) and is_binary(key) do
    case Cachex.get(cache_name, key) do
      {:ok, value} when is_binary(value) or is_nil(value) -> {:ok, value}
      {:ok, value} -> {:ok, to_string(value)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec increment(cache_name(), String.t(), pos_integer()) :: {:ok, integer()} | {:error, term()}
  def increment(cache_name, key, ttl_seconds)
      when is_atom(cache_name) and is_binary(key) and is_integer(ttl_seconds) and
             ttl_seconds > 0 do
    current =
      case Cachex.get(cache_name, key) do
        {:ok, value} -> parse_integer(value)
        {:error, _reason} -> 0
      end

    next = current + 1

    case Cachex.put(cache_name, key, Integer.to_string(next), ttl: :timer.seconds(ttl_seconds)) do
      {:ok, true} -> {:ok, next}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec set_add(cache_name(), String.t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def set_add(cache_name, key, member, ttl_seconds)
      when is_atom(cache_name) and is_binary(key) and is_binary(member) and
             is_integer(ttl_seconds) and ttl_seconds > 0 do
    members =
      case Cachex.get(cache_name, key) do
        {:ok, existing} when is_list(existing) -> MapSet.new(existing)
        _ -> MapSet.new()
      end
      |> MapSet.put(member)
      |> MapSet.to_list()

    case Cachex.put(cache_name, key, members, ttl: :timer.seconds(ttl_seconds)) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec set_remove(cache_name(), String.t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def set_remove(cache_name, key, member, ttl_seconds)
      when is_atom(cache_name) and is_binary(key) and is_binary(member) and
             is_integer(ttl_seconds) and ttl_seconds > 0 do
    members =
      case Cachex.get(cache_name, key) do
        {:ok, existing} when is_list(existing) -> existing
        _ -> []
      end
      |> Enum.reject(&(&1 == member))

    case Cachex.put(cache_name, key, members, ttl: :timer.seconds(ttl_seconds)) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec set_members(cache_name(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def set_members(cache_name, key) when is_atom(cache_name) and is_binary(key) do
    case Cachex.get(cache_name, key) do
      {:ok, members} when is_list(members) -> {:ok, Enum.filter(members, &is_binary/1)}
      {:ok, nil} -> {:ok, []}
      {:ok, _value} -> {:error, :invalid_cached_set}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec digest(term()) :: String.t()
  def digest(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> 0
    end
  end

  defp parse_integer(_value), do: 0

  defp log_put_error(cache_name, key, reason) do
    Logger.debug(
      "cache put failed cache=#{cache_name} key_hash=#{digest(key)}: #{inspect(reason)}"
    )

    {:error, reason}
  end
end
