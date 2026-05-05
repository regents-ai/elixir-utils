defmodule Xmtp.Metadata.GroupAppData do
  @moduledoc """
  Regent group appData codec.

  The appData document is a small JSON object with one Regent-owned section.
  Product apps can put room and member display metadata here without exposing
  raw XMTP group internals to UI code.
  """

  @schema "regent.xmtp.group_app_data.v1"

  @spec encode(map()) :: {:ok, String.t()} | {:error, term()}
  def encode(attrs) when is_map(attrs) do
    attrs
    |> normalize()
    |> Jason.encode()
  end

  @spec decode(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def decode(nil), do: {:ok, empty()}
  def decode(""), do: {:ok, empty()}

  def decode(data) when is_binary(data) do
    with {:ok, decoded} <- Jason.decode(data) do
      {:ok, normalize(decoded)}
    end
  end

  @spec put_member_profile(String.t() | nil, String.t(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def put_member_profile(app_data, principal_id, profile)
      when is_binary(principal_id) and is_map(profile) do
    with {:ok, decoded} <- decode(app_data) do
      decoded
      |> put_in([:member_profiles, principal_id], profile)
      |> encode()
    end
  end

  @spec get_member_profile(String.t() | nil, String.t()) :: {:ok, map() | nil} | {:error, term()}
  def get_member_profile(app_data, principal_id) when is_binary(principal_id) do
    with {:ok, decoded} <- decode(app_data) do
      {:ok, get_in(decoded, [:member_profiles, principal_id])}
    end
  end

  defp normalize(attrs) do
    %{
      schema: @schema,
      product: fetch(attrs, :product),
      room_key: fetch(attrs, :room_key),
      room_profile: fetch(attrs, :room_profile) || %{},
      member_profiles: fetch(attrs, :member_profiles) || %{}
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp empty do
    %{schema: @schema, room_profile: %{}, member_profiles: %{}}
  end

  defp fetch(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end
end
