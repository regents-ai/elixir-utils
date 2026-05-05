defmodule Xmtp.Metadata.Profile do
  @moduledoc """
  Regent profile metadata codec for silent profile updates and room display.
  """

  alias Xmtp.Principal

  @type product :: :platform | :autolaunch | :techtree

  @type t :: %{
          required(:schema) => String.t(),
          required(:product) => product(),
          required(:principal_type) => :human | :agent,
          required(:principal_id) => String.t(),
          optional(:display_name) => String.t(),
          optional(:avatar_url) => String.t(),
          optional(:profile_url) => String.t(),
          optional(:wallet_address) => String.t(),
          optional(:inbox_id) => String.t(),
          optional(:overlays) => map()
        }

  @schema "regent.xmtp.profile.v1"

  @spec encode_regent_profile(map()) :: {:ok, String.t()} | {:error, term()}
  def encode_regent_profile(attrs) when is_map(attrs) do
    with {:ok, profile} <- normalize(attrs) do
      Jason.encode(profile)
    end
  end

  @spec decode(String.t()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_binary(data) do
    with {:ok, decoded} <- Jason.decode(data),
         {:ok, profile} <- normalize(decoded) do
      {:ok, profile}
    end
  end

  @spec silent_message(map()) :: {:ok, map()} | {:error, term()}
  def silent_message(attrs) do
    with {:ok, encoded} <- encode_regent_profile(attrs) do
      {:ok, %{kind: :regent_profile, silent?: true, body: encoded}}
    end
  end

  defp normalize(attrs) do
    with {:ok, product} <- normalize_product(fetch(attrs, :product)),
         {:ok, principal_type} <- normalize_principal_type(fetch(attrs, :principal_type)),
         {:ok, principal_id} <- required_string(attrs, :principal_id) do
      {:ok,
       %{
         schema: @schema,
         product: product,
         principal_type: principal_type,
         principal_id: principal_id,
         display_name: optional_string(attrs, :display_name),
         avatar_url: optional_string(attrs, :avatar_url),
         profile_url: optional_string(attrs, :profile_url),
         wallet_address: Principal.normalize_wallet(fetch(attrs, :wallet_address)),
         inbox_id: optional_string(attrs, :inbox_id),
         overlays: fetch(attrs, :overlays) || %{}
       }
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)
       |> Map.new()}
    end
  end

  defp normalize_product(product) when product in [:platform, :autolaunch, :techtree],
    do: {:ok, product}

  defp normalize_product("platform"), do: {:ok, :platform}
  defp normalize_product("autolaunch"), do: {:ok, :autolaunch}
  defp normalize_product("techtree"), do: {:ok, :techtree}

  defp normalize_product(_product), do: {:error, :invalid_product}

  defp normalize_principal_type(type) when type in [:human, :agent], do: {:ok, type}

  defp normalize_principal_type("human"), do: {:ok, :human}
  defp normalize_principal_type("agent"), do: {:ok, :agent}

  defp normalize_principal_type(_type), do: {:error, :invalid_principal_type}

  defp required_string(attrs, key) do
    case optional_string(attrs, key) do
      nil -> {:error, {:missing, key}}
      value -> {:ok, value}
    end
  end

  defp optional_string(attrs, key) do
    attrs
    |> fetch(key)
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _value ->
        nil
    end
  end

  defp fetch(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end
end
