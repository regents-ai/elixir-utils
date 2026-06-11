# RegentFormat

Shared display formatting helpers for Regent Elixir apps.

`RegentFormat` is the single home for null-safe display values, `0x`
address/hash truncation, decimal and currency rendering, timestamp
formatting, and identity monograms. Product copy, CSS tone classes, and
domain-specific labels stay in the consuming app.

## Usage

Add the path dependency:

```elixir
{:regent_format, path: "../elixir-utils/format"}
```

Then call the helpers directly, or alias the module where a shorter name
reads better in templates:

```elixir
alias RegentFormat, as: Format

Format.format_currency("1234.5", 2)
#=> "$1,234.50"

Format.short_wallet("0x1234567890abcdef1234567890abcdef12345678")
#=> "0x1234...5678"

Format.format_datetime("2026-01-05T15:04:05Z", :date, "Unknown")
#=> "Jan 5, 2026"
```

## Development

```sh
mix deps.get
mix precommit
```
