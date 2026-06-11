defmodule RegentFormatTest do
  use ExUnit.Case, async: true

  doctest RegentFormat

  describe "blank_to_nil/1" do
    test "converts blanks and passes values through" do
      assert RegentFormat.blank_to_nil(nil) == nil
      assert RegentFormat.blank_to_nil("") == nil
      assert RegentFormat.blank_to_nil("value") == "value"
      assert RegentFormat.blank_to_nil(0) == 0
    end
  end

  describe "display/2" do
    test "substitutes the empty marker for nil and blank" do
      assert RegentFormat.display(nil) == "-"
      assert RegentFormat.display("") == "-"
      assert RegentFormat.display(nil, "n/a") == "n/a"
    end

    test "stringifies non-blank values" do
      assert RegentFormat.display("ready") == "ready"
      assert RegentFormat.display(42) == "42"
    end
  end

  describe "display_uint/1 and display_int/1" do
    test "use n/a for missing values" do
      assert RegentFormat.display_uint(nil) == "n/a"
      assert RegentFormat.display_int(nil) == "n/a"
      assert RegentFormat.display_uint(7) == "7"
      assert RegentFormat.display_int(-7) == "-7"
    end
  end

  describe "display_seconds/1" do
    test "labels integer durations" do
      assert RegentFormat.display_seconds(nil) == "n/a"
      assert RegentFormat.display_seconds(90) == "90 seconds"
      assert RegentFormat.display_seconds("soon") == "soon"
    end
  end

  describe "display_bps_percent/1" do
    test "converts basis points to percent" do
      assert RegentFormat.display_bps_percent(nil) == "n/a"
      assert RegentFormat.display_bps_percent(0) == "n/a"
      assert RegentFormat.display_bps_percent(250) == "2.5%"
      assert RegentFormat.display_bps_percent(10_000) == "100%"
    end
  end

  describe "display_unix_timestamp/1" do
    test "renders unix seconds in UTC" do
      assert RegentFormat.display_unix_timestamp(nil) == "n/a"
      assert RegentFormat.display_unix_timestamp(0) == "n/a"
      assert RegentFormat.display_unix_timestamp(1_767_625_445) == "2026-01-05 15:04:05 UTC"
    end
  end

  describe "display_datetime/1" do
    test "renders ISO8601 strings and passes through unparseable values" do
      assert RegentFormat.display_datetime(nil) == nil
      assert RegentFormat.display_datetime("2026-01-05T15:04:05Z") == "Jan 5, 2026 at 3:04 PM UTC"
      assert RegentFormat.display_datetime("not a date") == "not a date"
    end
  end

  describe "display_chart_date/1" do
    test "renders dates with a scheduled fallback" do
      assert RegentFormat.display_chart_date(nil) == "Scheduled date"
      assert RegentFormat.display_chart_date(~U[2026-01-05 15:04:05Z]) == "Jan 5, 2026"
      assert RegentFormat.display_chart_date("2026-01-05T15:04:05Z") == "Jan 5, 2026"
      assert RegentFormat.display_chart_date("soon") == "soon"
    end
  end

  describe "parse_datetime/1" do
    test "accepts DateTime structs and ISO8601 binaries" do
      assert RegentFormat.parse_datetime(~U[2026-01-05 15:04:05Z]) == ~U[2026-01-05 15:04:05Z]
      assert RegentFormat.parse_datetime("2026-01-05T15:04:05Z") == ~U[2026-01-05 15:04:05Z]
      assert RegentFormat.parse_datetime("not a date") == nil
      assert RegentFormat.parse_datetime(nil) == nil
      assert RegentFormat.parse_datetime(123) == nil
    end
  end

  describe "format_datetime/3" do
    test "formats each style" do
      value = "2026-01-05T15:04:05Z"

      assert RegentFormat.format_datetime(value, :date) == "Jan 5, 2026"
      assert RegentFormat.format_datetime(value, :time) == "15:04 UTC"
      assert RegentFormat.format_datetime(value, :datetime) == "Jan 5, 2026 03:04 PM UTC"
      assert RegentFormat.format_datetime(value, :datetime_seconds) == "Jan 5, 15:04:05 UTC"
      assert RegentFormat.format_datetime(value, :short) == "Jan 5"
    end

    test "returns the fallback for missing or unparseable values" do
      assert RegentFormat.format_datetime(nil, :date) == nil
      assert RegentFormat.format_datetime(nil, :date, "Unknown") == "Unknown"
      assert RegentFormat.format_datetime("not a date", :time, "Unknown") == "Unknown"
    end
  end

  describe "yes_no/1" do
    test "labels booleans" do
      assert RegentFormat.yes_no(true) == "yes"
      assert RegentFormat.yes_no(false) == "no"
      assert RegentFormat.yes_no(nil) == "n/a"
    end
  end

  describe "humanize_key/1" do
    test "capitalizes snake_case keys" do
      assert RegentFormat.humanize_key(:minimum_raise_quote) == "Minimum Raise Quote"
      assert RegentFormat.humanize_key("agent_safe_address") == "Agent Safe Address"
    end
  end

  describe "monogram/2" do
    test "takes the first letters of up to two words" do
      assert RegentFormat.monogram("Helios Relay", "AL") == "HR"
      assert RegentFormat.monogram("atlas-prime-search", "AL") == "AP"
      assert RegentFormat.monogram("solo", "AL") == "S"
    end

    test "falls back when no initials can be derived" do
      assert RegentFormat.monogram(nil, "AL") == "AL"
      assert RegentFormat.monogram("", "AL") == "AL"
      assert RegentFormat.monogram("   ", "AL") == "AL"
      assert RegentFormat.monogram(%{}, "AL") == "AL"
    end
  end

  describe "short_address/2" do
    test "truncates long 0x addresses" do
      assert RegentFormat.short_address("0x1234567890abcdef1234567890abcdef12345678") ==
               "0x123456...5678"
    end

    test "substitutes the empty marker and passes short values through" do
      assert RegentFormat.short_address(nil) == "n/a"
      assert RegentFormat.short_address(nil, "none") == "none"
      assert RegentFormat.short_address("0xabc") == "0xabc"
      assert RegentFormat.short_address("vault.eth") == "vault.eth"
    end
  end

  describe "short_wallet/1" do
    test "truncates wallets and trims whitespace" do
      assert RegentFormat.short_wallet(" 0x1234567890abcdef1234567890abcdef12345678 ") ==
               "0x1234...5678"
    end

    test "returns nil for non-binaries and passes short values through" do
      assert RegentFormat.short_wallet(nil) == nil
      assert RegentFormat.short_wallet(123) == nil
      assert RegentFormat.short_wallet("0xabc") == "0xabc"
    end
  end

  describe "short_hash/2" do
    test "truncates long 0x hashes" do
      hash = "0x" <> String.duplicate("ab", 32)
      assert RegentFormat.short_hash(hash) == "0xabababab...ababab"
    end

    test "substitutes the empty marker and passes short values through" do
      assert RegentFormat.short_hash(nil) == "none"
      assert RegentFormat.short_hash(nil, "n/a") == "n/a"
      assert RegentFormat.short_hash("0xabcdef") == "0xabcdef"
    end
  end

  describe "parse_decimal/1" do
    test "parses integers, binaries, and Decimals" do
      assert RegentFormat.parse_decimal(42) == Decimal.new(42)
      assert RegentFormat.parse_decimal("42.5") == Decimal.new("42.5")
      assert RegentFormat.parse_decimal(Decimal.new("1.5")) == Decimal.new("1.5")
      assert Decimal.equal?(RegentFormat.parse_decimal("9.5E+2"), Decimal.new(950))
    end

    test "returns nil for blank or unparseable values" do
      assert RegentFormat.parse_decimal(nil) == nil
      assert RegentFormat.parse_decimal("") == nil
      assert RegentFormat.parse_decimal("12 tokens") == nil
      assert RegentFormat.parse_decimal(:atom) == nil
    end
  end

  describe "format_currency/2" do
    test "renders dollar amounts with delimiters" do
      assert RegentFormat.format_currency("1234567.891", 2) == "$1,234,567.89"
      assert RegentFormat.format_currency(50, 0) == "$50"
      assert RegentFormat.format_currency(Decimal.new("0.5"), 2) == "$0.50"
    end

    test "returns Unavailable for missing or unparseable values" do
      assert RegentFormat.format_currency(nil, 2) == "Unavailable"
      assert RegentFormat.format_currency("soon", 2) == "Unavailable"
    end
  end

  describe "decimal_to_string/2" do
    test "pads and truncates to the requested places" do
      assert RegentFormat.decimal_to_string(Decimal.new("1.5"), 3) == "1.500"
      assert RegentFormat.decimal_to_string(Decimal.new("1.23456"), 2) == "1.23"
      assert RegentFormat.decimal_to_string(Decimal.new("7"), 2) == "7.00"
      assert RegentFormat.decimal_to_string(Decimal.new("7.4"), 0) == "7"
    end
  end

  describe "add_delimiters/1" do
    test "inserts comma delimiters into the whole part" do
      assert RegentFormat.add_delimiters("1234567.89") == "1,234,567.89"
      assert RegentFormat.add_delimiters("1234") == "1,234"
      assert RegentFormat.add_delimiters("123") == "123"
      assert RegentFormat.add_delimiters("-1234.5") == "-1,234.5"
    end
  end
end
