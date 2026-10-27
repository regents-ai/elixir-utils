# Changelog

## 0.1.0 (unreleased)

- `RegentPoints.Amount.format/1` is exact at any size. It divided micro-Points
  by 1,000,000 with Decimal's 34-digit precision, so an amount longer than 34
  digits was rounded half up and a page could show more Points than there are
  ("100,000,…,000.00" for "99,999,…,999.99"). It now moves the decimal point six
  places, as `RegentFormat` does since its exact-at-any-size change.
- `RegentPoints.Amount.format/1` shows Points the one Regent way
  (`RegentFormat.amount/1`): "1,234.56", "0.400".
