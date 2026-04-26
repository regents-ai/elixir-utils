defmodule Xmtp.Principal do
  @moduledoc false

  @type kind :: :human | :agent | :system

  @type t :: %__MODULE__{
          id: term() | nil,
          kind: kind(),
          wallet_address: String.t() | nil,
          wallet_addresses: [String.t()],
          inbox_id: String.t() | nil,
          display_name: String.t() | nil,
          metadata: map()
        }

  defstruct id: nil,
            kind: :human,
            wallet_address: nil,
            wallet_addresses: [],
            inbox_id: nil,
            display_name: nil,
            metadata: %{}

  @field_keys [
    :id,
    :kind,
    :wallet_address,
    :wallet_addresses,
    :inbox_id,
    :display_name,
    :metadata
  ]
  @string_field_keys Map.new(@field_keys, &{Atom.to_string(&1), &1})

  @spec from(nil | t() | map()) :: nil | t()
  def from(nil), do: nil
  def from(%__MODULE__{} = principal), do: normalize(principal)

  def from(%{} = attrs) do
    attrs
    |> normalize_attrs()
    |> then(fn normalized ->
      kind = Map.get(normalized, :kind, :human)

      %__MODULE__{
        id: Map.get(normalized, :id),
        kind: normalize_kind(kind),
        wallet_address: Map.get(normalized, :wallet_address),
        wallet_addresses: List.wrap(Map.get(normalized, :wallet_addresses, [])),
        inbox_id: Map.get(normalized, :inbox_id),
        display_name: Map.get(normalized, :display_name),
        metadata: Map.get(normalized, :metadata, %{})
      }
      |> normalize()
    end)
  end

  @spec human(map()) :: t()
  def human(attrs), do: from(Map.put(attrs, :kind, :human))

  @spec agent(map()) :: t()
  def agent(attrs), do: from(Map.put(attrs, :kind, :agent))

  @spec wallet(t() | nil) :: String.t() | nil
  def wallet(nil), do: nil

  def wallet(%__MODULE__{wallet_address: wallet_address, wallet_addresses: wallet_addresses}) do
    [wallet_address | wallet_addresses]
    |> Enum.find_value(&normalize_wallet/1)
  end

  @spec kind(t() | nil) :: kind() | nil
  def kind(nil), do: nil
  def kind(%__MODULE__{kind: kind}), do: kind

  @spec label(t() | nil) :: String.t()
  def label(nil), do: "guest"

  def label(%__MODULE__{display_name: display_name} = principal) when is_binary(display_name) do
    trimmed = String.trim(display_name)
    if trimmed == "", do: short(wallet(principal)), else: trimmed
  end

  def label(%__MODULE__{} = principal), do: short(wallet(principal))

  @spec short(String.t() | nil) :: String.t()
  def short(nil), do: "guest"

  def short(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.length(trimmed) <= 12 do
      trimmed
    else
      "#{String.slice(trimmed, 0, 6)}...#{String.slice(trimmed, -4, 4)}"
    end
  end

  @spec normalize_wallet(String.t() | nil) :: String.t() | nil
  def normalize_wallet(nil), do: nil

  def normalize_wallet(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      wallet -> String.downcase(wallet)
    end
  end

  def normalize_wallet(_value), do: nil

  defp normalize(%__MODULE__{} = principal) do
    wallet_address = normalize_wallet(principal.wallet_address)

    wallet_addresses =
      principal.wallet_addresses
      |> List.wrap()
      |> Enum.map(&normalize_wallet/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %__MODULE__{
      principal
      | wallet_address: wallet_address || List.first(wallet_addresses),
        wallet_addresses:
          Enum.uniq([wallet_address | wallet_addresses] |> Enum.reject(&is_nil/1)),
        kind: normalize_kind(principal.kind),
        display_name: normalize_label(principal.display_name),
        metadata: principal.metadata || %{}
    }
  end

  defp normalize_kind(:human), do: :human
  defp normalize_kind(:agent), do: :agent
  defp normalize_kind(:system), do: :system
  defp normalize_kind("human"), do: :human
  defp normalize_kind("agent"), do: :agent
  defp normalize_kind("system"), do: :system
  defp normalize_kind(_), do: :human

  defp normalize_label(nil), do: nil

  defp normalize_label(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_label(_value), do: nil

  defp normalize_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) and key in @field_keys ->
        Map.put(acc, key, value)

      {key, value}, acc when is_binary(key) ->
        case Map.fetch(@string_field_keys, key) do
          {:ok, normalized_key} -> Map.put(acc, normalized_key, value)
          :error -> acc
        end

      _entry, acc ->
        acc
    end)
  end
end
