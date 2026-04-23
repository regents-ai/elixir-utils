defmodule RegentCache do
  @moduledoc """
  Shared Dragonfly-backed cache helpers for Regent Elixir applications.
  """

  alias RegentCache.Dragonfly

  @type app_name :: atom()

  @spec fetch(app_name(), String.t(), pos_integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def fetch(app, key, ttl_seconds, fun)
      when is_atom(app) and is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0 and
             is_function(fun, 0) do
    case get_json(app, key) do
      {:ok, value} ->
        {:ok, value}

      :miss ->
        with {:ok, value} <- fun.() do
          _ = put_json(app, key, value, ttl_seconds)
          {:ok, value}
        end

      {:error, _reason} ->
        fun.()
    end
  end

  @spec get_json(app_name(), String.t()) :: {:ok, term()} | :miss | {:error, term()}
  def get_json(app, key) when is_atom(app) and is_binary(key) do
    case Dragonfly.get(app, key) do
      {:ok, nil} ->
        :miss

      {:ok, value} when is_binary(value) ->
        case Jason.decode(value, keys: :atoms) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, reason}
        end

      {:error, :dragonfly_disabled} ->
        :miss

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec put_json(app_name(), String.t(), term(), pos_integer()) :: :ok | {:error, term()}
  def put_json(app, key, value, ttl_seconds)
      when is_atom(app) and is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    with {:ok, encoded} <- Jason.encode(value) do
      Dragonfly.set(app, key, encoded, ttl_seconds)
    end
  end

  @spec delete(app_name(), String.t() | [String.t()]) :: :ok | {:error, term()}
  def delete(app, keys) when is_atom(app), do: Dragonfly.delete(app, keys)

  @spec digest(term()) :: String.t()
  def digest(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
