# RegentFormat

Shared display formatting helpers for Regent Elixir apps.

`RegentFormat` is the single home for null-safe display values, `0x`
address/hash truncation, decimal and currency rendering, timestamp
formatting, relative times, and identity monograms. Every short address
takes one form, `0x1234..abcd`: `0x`, the first four and the last four
characters, joined by two full stops. Product copy, CSS tone classes, and
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

Format.short_address("0x1234567890abcdef1234567890abcdef1234abcd")
#=> "0x1234..abcd"

Format.relative_time(~U[2026-01-05 15:01:05Z], ~U[2026-01-05 15:04:05Z])
#=> "3 minutes ago"

Format.format_datetime("2026-01-05T15:04:05Z", :date, "Unknown")
#=> "Jan 5, 2026"
```

## Development

```sh
mix deps.get
mix check
```
