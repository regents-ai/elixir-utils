defmodule RegentFormat do
  @moduledoc """
  Display formatting helpers shared across Regent Elixir apps.

  Covers null-safe display values, address/hash truncation, decimal and
  currency rendering, timestamp formatting, and short identity monograms.
  All functions are pure and return strings (or `nil` where documented);
  product-specific copy and CSS concerns stay in the consuming app.
  """

  alias Decimal, as: D

  @datetime_styles %{
    date: "%b %-d, %Y",
    time: "%H:%M UTC",
    datetime: "%b %-d, %Y %I:%M %p UTC",
    datetime_seconds: "%b %-d, %H:%M:%S UTC",
    short: "%b %-d"
  }

  @doc """
  Converts blank values to `nil`, passing everything else through.

      iex> RegentFormat.blank_to_nil("")
      nil

      iex> RegentFormat.blank_to_nil("ok")
      "ok"
  """
  def blank_to_nil(nil), do: nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value

  @doc """
  Renders a value as a string, substituting `empty` for `nil` or `""`.

      iex> RegentFormat.display(nil)
      "-"

      iex> RegentFormat.display(42, "n/a")
      "42"
  """
  def display(value, empty \\ "-")

  def display(nil, empty), do: empty
  def display("", empty), do: empty
  def display(value, _empty) when is_binary(value), do: value
  def display(value, _empty), do: to_string(value)

  @doc "Renders an unsigned integer value, with `\"n/a\"` for `nil`/blank."
  def display_uint(value), do: display(value, "n/a")

  @doc "Renders an integer value, with `\"n/a\"` for `nil`/blank."
  def display_int(value), do: display(value, "n/a")

  @doc """
  Renders a duration in seconds, e.g. `"90 seconds"`, with `"n/a"` for `nil`.
  """
  def display_seconds(nil), do: "n/a"
  def display_seconds(value) when is_integer(value), do: Integer.to_string(value) <> " seconds"
  def display_seconds(value), do: to_string(value)

  @doc """
  Renders basis points as a percentage, e.g. `250` -> `"2.5%"`.

      iex> RegentFormat.display_bps_percent(250)
      "2.5%"
  """
  def display_bps_percent(nil), do: "n/a"
  def display_bps_percent(0), do: "n/a"

  def display_bps_percent(value) when is_integer(value) do
    value
    |> D.new()
    |> D.div(D.new(100))
    |> D.normalize()
    |> D.to_string(:normal)
    |> Kernel.<>("%")
  end

  def display_bps_percent(value), do: to_string(value)

  @doc """
  Renders a unix timestamp as `"YYYY-MM-DD HH:MM:SS UTC"`, with `"n/a"` for
  `nil` or `0`.
  """
  def display_unix_timestamp(nil), do: "n/a"
  def display_unix_timestamp(0), do: "n/a"

  def display_unix_timestamp(value) when is_integer(value) and value > 0 do
    value
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  rescue
    _ -> Integer.to_string(value)
  end

  def display_unix_timestamp(value), do: to_string(value)

  @doc """
  Renders an ISO8601 string as `"Jan 5, 2026 at 3:04 PM UTC"`, passing the
  input through when it cannot be parsed and returning `nil` for `nil`.
  """
  def display_datetime(nil), do: nil

  def display_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%b %-d, %Y at %-I:%M %p UTC")
      _ -> value
    end
  end

  @doc """
  Renders a chart axis date as `"Jan 5, 2026"`, with `"Scheduled date"` for
  `nil` and pass-through for unparseable strings.
  """
  def display_chart_date(%DateTime{} = value), do: Calendar.strftime(value, "%b %-d, %Y")
  def display_chart_date(nil), do: "Scheduled date"

  def display_chart_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%b %-d, %Y")
      _ -> value
    end
  end

  @doc """
  Parses an ISO8601 binary or passes through a `DateTime`; anything else
  (including unparseable strings) returns `nil`.
  """
  def parse_datetime(%DateTime{} = value), do: value

  def parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  def parse_datetime(_value), do: nil

  @doc """
  Formats a `DateTime` or ISO8601 binary in one of the shared styles,
  returning `fallback` when the value cannot be parsed.

  Styles: `:date` (`"Jan 5, 2026"`), `:time` (`"15:04 UTC"`), `:datetime`
  (`"Jan 5, 2026 03:04 PM UTC"`), `:datetime_seconds`
  (`"Jan 5, 15:04:05 UTC"`), `:short` (`"Jan 5"`).

      iex> RegentFormat.format_datetime("2026-01-05T15:04:05Z", :date)
      "Jan 5, 2026"

      iex> RegentFormat.format_datetime("not a date", :time, "Unknown")
      "Unknown"
  """
  def format_datetime(value, style, fallback \\ nil) when is_map_key(@datetime_styles, style) do
    case parse_datetime(value) do
      nil -> fallback
      datetime -> Calendar.strftime(datetime, Map.fetch!(@datetime_styles, style))
    end
  end

  @doc """
  Renders booleans as `"yes"`/`"no"`, with `"n/a"` for `nil`.
  """
  def yes_no(true), do: "yes"
  def yes_no(false), do: "no"
  def yes_no(nil), do: "n/a"

  @doc """
  Turns a snake_case key into capitalized words.

      iex> RegentFormat.humanize_key(:minimum_raise_quote)
      "Minimum Raise Quote"
  """
  def humanize_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Builds a one-or-two-letter monogram from a name, e.g. `"Helios Relay"` ->
  `"HR"`. Returns `fallback` when no initials can be derived.

      iex> RegentFormat.monogram("Helios Relay", "AL")
      "HR"

      iex> RegentFormat.monogram(nil, "AL")
      "AL"
  """
  def monogram(name, fallback) when is_binary(name) do
    name
    |> String.split(~r/[\s-]+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
    |> case do
      "" -> fallback
      initials -> initials
    end
  end

  def monogram(_name, fallback), do: fallback

  @doc """
  Truncates a `0x` address to `"0x123456...abcd"`, substituting `empty` for
  `nil` and passing through values that are not long `0x` strings.
  """
  def short_address(value, empty \\ "n/a")

  def short_address(nil, empty), do: empty

  def short_address("0x" <> _rest = value, _empty) when byte_size(value) > 12 do
    String.slice(value, 0, 8) <> "..." <> String.slice(value, -4, 4)
  end

  def short_address(value, _empty), do: to_string(value)

  @doc """
  Truncates a wallet address to `"0x1234...abcd"`. Returns `nil` for anything
  that is not a binary.
  """
  def short_wallet(nil), do: nil

  def short_wallet(wallet) when is_binary(wallet) do
    wallet
    |> String.trim()
    |> do_short_wallet()
  end

  def short_wallet(_wallet), do: nil

  defp do_short_wallet("0x" <> rest = wallet) when byte_size(rest) > 10 do
    String.slice(wallet, 0, 6) <> "..." <> String.slice(wallet, -4, 4)
  end

  defp do_short_wallet(wallet), do: wallet

  @doc """
  Truncates a `0x` hash to `"0x12345678...abcdef"`, substituting `empty` for
  `nil` and passing through values that are not long `0x` strings.
  """
  def short_hash(value, empty \\ "none")

  def short_hash(nil, empty), do: empty

  def short_hash("0x" <> _rest = value, _empty) when byte_size(value) > 14 do
    String.slice(value, 0, 10) <> "..." <> String.slice(value, -6, 6)
  end

  def short_hash(value, _empty), do: to_string(value)

  @doc """
  Parses integers, binaries, and `Decimal` structs into a `Decimal`, returning
  `nil` for blank or unparseable values.

      iex> RegentFormat.parse_decimal("9.5E+2")
      Decimal.new("9.5E+2")

      iex> RegentFormat.parse_decimal("not a number")
      nil
  """
  def parse_decimal(nil), do: nil
  def parse_decimal(""), do: nil
  def parse_decimal(value) when is_integer(value), do: D.new(value)
  def parse_decimal(%D{} = value), do: value

  def parse_decimal(value) when is_binary(value) do
    case D.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  def parse_decimal(_value), do: nil

  @doc """
  Renders a value as a dollar amount with thousands delimiters and a fixed
  number of decimal places, e.g. `"$1,234.50"`. Returns `"Unavailable"` for
  values that cannot be parsed.
  """
  def format_currency(nil, _places), do: "Unavailable"

  def format_currency(value, places) do
    case parse_decimal(value) do
      nil ->
        "Unavailable"

      decimal ->
        "$" <>
          (decimal
           |> D.round(places)
           |> decimal_to_string(places)
           |> add_delimiters())
    end
  end

  @doc """
  Renders a `Decimal` in plain notation padded or truncated to `places`
  decimal places.
  """
  def decimal_to_string(decimal, 0), do: decimal |> D.round(0) |> D.to_string(:normal)

  def decimal_to_string(decimal, places) do
    string = D.to_string(decimal, :normal)

    case String.split(string, ".", parts: 2) do
      [whole, fraction] ->
        padded =
          fraction
          |> String.pad_trailing(places, "0")
          |> String.slice(0, places)

        whole <> "." <> padded

      [whole] ->
        whole <> "." <> String.duplicate("0", places)
    end
  end

  @doc """
  Inserts comma thousands delimiters into a plain numeric string.

      iex> RegentFormat.add_delimiters("1234567.89")
      "1,234,567.89"
  """
  def add_delimiters("-" <> rest), do: "-" <> add_delimiters(rest)

  def add_delimiters(value) do
    case String.split(value, ".", parts: 2) do
      [whole, fraction] -> add_delimiters_to_whole(whole) <> "." <> fraction
      [whole] -> add_delimiters_to_whole(whole)
    end
  end

  defp add_delimiters_to_whole(whole) do
    whole
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
