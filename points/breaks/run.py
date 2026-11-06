"""Deliberate breaks in dollar points, each of which the spending tests must catch.

Run from anywhere, with the package's Elixir and Postgres on PATH:

    python3 -I breaks/run.py            # every break
    python3 -I breaks/run.py 06 C2      # only these

Each break changes one piece of the library or the migration, runs
test/regent_points/spending_test.exs, then writes the original back. A break the
tests stay green on is MISSED. Breaks in the migration run on their own test
database, made fresh before each and removed after. It is not part of `mix check`.

Exit 0 means the unbroken tests are green before and after, and every break was
caught.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ["test/regent_points/spending_test.exs", "--seed", "0"]

AWD = "lib/regent_points/award.ex"
INT = "lib/regent_points/intake_worker.ex"
REV = "lib/regent_points/reverse.ex"
RUL = "lib/regent_points/rules.ex"
STO = "lib/regent_points/store.ex"
MIG = "priv/repo/migrations/20261106172400_payment_once.exs"

PAYER = 'text?(payer, ~r/\\A0x[0-9a-f]{40}\\z/)'
PRICE = 'text?(price, ~r/\\A(0|[1-9][0-9]{0,29})(\\.[0-9]{1,30})?\\z/)'
FREES = "if used_payment?(original) and args.points_micro == remaining do"
RELEASE = "Points.release_cap!(payment, original.points_micro_delta, actor: Store.system())"
USES = 'base > 0 or (kind == :payment and reason != "allowance_used")'
SITE = 'facts.source_app != hd(String.split(id, ".")) ->'
DIV = """    div(
      String.to_integer(amount) * String.to_integer(digits) * 1_000_000,
      10 ** (places + decimals)
    )"""

# (name, file, original text, broken text). The first two characters name a break.
# Not here: token decimals above 255 accepted. No accepted token amount (78 digits)
# and price (30 digits each side) gives such decimals anything but 0 dollars, which
# is refused either way, so no test can tell that break apart.
BREAKS = [
    ("01 a full take-back never frees the payment", REV, FREES,
     "if used_payment?(original) and args.points_micro == remaining and original.id == nil do"),
    ("02 a partial take-back frees the payment", REV, FREES,
     "if used_payment?(original) and args.points_micro > 0 do"),
    ("03 a 0 correction of a repeat's entry frees the real holder's payment", REV,
     'do: entry.category == "spending" and entry.reason_code != "allowance_used"',
     'do: entry.category == "spending"'),
    ("04 a 0 correction is written for a repeat's entry", REV,
     "do: used_payment?(original)\n", 'do: original.category == "spending"\n'),
    ("05 a 0 correction is written for any 0-point entry", REV,
     "do: used_payment?(original)\n", "do: is_map(original)\n"),
    ("06 a second 0 correction is allowed", REV,
     "if args.points_micro > remaining or (corrected != nil and remaining == 0) do",
     "if args.points_micro > remaining do"),
    ("07 a report that found the day full does not use its payment", AWD, USES, "base > 0"),
    ("08 the dollars round up instead of down", INT, DIV,
     """    -Integer.floor_div(
      -(String.to_integer(amount) * String.to_integer(digits) * 1_000_000),
      10 ** (places + decimals)
    )"""),
    ("09 the dollars treat every token as 18 decimals or 6", INT,
     "10 ** (places + decimals)", "10 ** (places + if(decimals > 12, do: 18, else: 6))"),
    ("10 the dollars are worked out with Decimal at its default 28 digits", INT, DIV,
     """    Decimal.new(amount)
    |> Decimal.mult(Decimal.new(price))
    |> Decimal.mult(1_000_000)
    |> Decimal.div(Decimal.new(10 ** decimals))
    |> Decimal.round(0, :floor)
    |> Decimal.to_integer()
    |> then(fn usd -> if {digits, places} == nil, do: 0, else: usd end)"""),
    ("11 a token amount may be longer than 78 digits", INT,
     "~r/\\A[1-9][0-9]{0,77}\\z/", "~r/\\A[1-9][0-9]*\\z/"),
    ("12 the paying wallet may use capital hex letters", INT, PAYER,
     'text?(payer, ~r/\\A0x[0-9a-fA-F]{40}\\z/)'),
    ("13 the paying wallet may be longer than 40 hex digits", INT, PAYER,
     'text?(payer, ~r/\\A0x[0-9a-f]{40,}\\z/)'),
    ("14 the paying wallet is any text at all", INT, PAYER, "text?(payer, ~r/./)"),
    ("15 any spending site may report any spending rule", INT, SITE,
     "facts.source_app not in ~w(keyfleet patchbay template autolaunch) ->"),
    ("16 Patchbay and Keyfleet may report each other's spending rules", INT, SITE,
     'facts.source_app != hd(String.split(id, ".")) and\n'
     '          Enum.sort([facts.source_app, hd(String.split(id, "."))]) != ~w(keyfleet patchbay) ->'),
    ("18 a take-back of an award the limit clipped does not free the payment", REV, FREES,
     "if used_payment?(original) and args.points_micro == remaining and\n"
     "           original.cap_reduction_micro == 0 do"),
    ("19 a 0 correction is written for a positive award", REV,
     "when points > 0,\n    do: by > 0", "when points > 0,\n    do: by >= 0"),
    ("20 the most a payment can prove is ten times higher", INT,
     "@most_usd_micros 1_000_000_000_000_000", "@most_usd_micros 10_000_000_000_000_000"),
    ("21 exactly a billion dollars is refused", INT,
     'facts.evidence["usd_micros"] > @most_usd_micros ->',
     'facts.evidence["usd_micros"] >= @most_usd_micros ->'),
    ("22 freeing a payment leaves its points on the row", REV, RELEASE,
     "Points.release_cap!(payment, 0, actor: Store.system())"),
    ("23 a completing partial take-back does not free the payment", REV, FREES,
     "if used_payment?(original) and args.points_micro == original.points_micro_delta do"),
    ("24 a token amount may start with zeros", INT,
     "~r/\\A[1-9][0-9]{0,77}\\z/", "~r/\\A[0-9]{1,78}\\z/"),
    ("25 a price may be written with an exponent", INT, PRICE,
     'text?(price, ~r/\\A(0|[1-9][0-9]{0,29})(\\.[0-9]{1,30})?(e0)?\\z/)'),
    ("26 the take-back of a payment's points reopens the day's room", REV, RELEASE,
     RELEASE + """

        Points.release_cap!(
          Store.cap(
            original.account_id,
            original.program_id,
            "spending:account",
            RegentPoints.Rules.window("day", original.earned_at)
          ),
          original.points_micro_delta,
          actor: Store.system()
        )"""),
    ("27 the price's whole part may be longer than 30 digits", INT, PRICE,
     'text?(price, ~r/\\A(0|[1-9][0-9]*)(\\.[0-9]{1,30})?\\z/)'),
    ("28 the price may have more than 30 places", INT, PRICE,
     'text?(price, ~r/\\A(0|[1-9][0-9]{0,29})(\\.[0-9]+)?\\z/)'),
    ("29 the price is any text", INT, PRICE + " and price =~ ~r/[1-9]/", "is_binary(price)"),
    ("30 the day comes from the check time, not the block", AWD,
     'Rules.window("day", event.source_action_at)', 'Rules.window("day", event.qualified_at)'),
    ("31 paying once ignores the log index", STO,
     "digest({chain, tx, log})", "digest({chain, tx, log * 0})"),
    ("32 paying once ignores the chain", STO,
     "digest({chain, tx, log})", "digest({chain * 0, tx, log})"),
    ("33 a chain id of any type", INT, "is_integer(chain) and chain > 0", "chain != nil"),
    ("34 capital letters in the transaction hash", INT,
     "text?(tx, ~r/\\A0x[0-9a-f]{64}\\z/)", "text?(tx, ~r/\\A0x[0-9a-fA-F]{64}\\z/)"),
    ("35 the token address is any text", INT,
     "text?(token, ~r/\\A0x[0-9a-f]{40}\\z/) and", "is_binary(token) and"),
    ("36 the block number is unchecked", INT, "is_integer(block) and\n      block > 0", "block != nil"),
    ("37 the log index is unchecked", INT, "is_integer(log) and log >= 0", "log != nil"),
    ("38 a blank price source", INT, "text?(source, ~r/\\S/)", "is_binary(source)"),
    ("39 a clipped payment is not marked used", AWD, USES,
     '(base > 0 and (kind != :payment or reason == "qualified"))'),
    ("40 a spending rule earns without approval", RUL,
     "def enabled?(id), do: id in Keyword.get(config(), :approved_rules, []) and adapter(id) != nil",
     'def enabled?(id), do: (String.ends_with?(id, "_spend") or '
     'id in Keyword.get(config(), :approved_rules, [])) and adapter(id) != nil'),
    ("41 a repeat writes no 0-point entry", AWD,
     '      {%{"category" => "milestone"}, {0, reason}} ->',
     '      {%{"category" => category}, {0, reason}} when category == "milestone" or '
     'reason == "allowance_used" ->'),
    ("42 the dollars are not checked against the amount and price", INT,
     'facts.evidence["usd_micros"] != dollars(facts.evidence) ->', "false ->"),
    ("43 a 0-point award cannot be corrected by 0", REV,
     "0),\n    do: used_payment?(original)", "0),\n    do: false"),
    ("44 no ceiling on a payment's dollars", INT,
     'facts.evidence["usd_micros"] > @most_usd_micros ->', "false ->"),
    ("D1 the database allows a 0 correction of any entry", MIG,
     "(points_micro_delta = 0 AND category = 'spending')", "points_micro_delta = 0"),
    ("D2 the database allows many 0 corrections of one entry", MIG,
     "CREATE UNIQUE INDEX IF NOT EXISTS point_entries_one_zero_correction_index",
     "CREATE INDEX IF NOT EXISTS point_entries_one_zero_correction_index"),
    ("D3 the database allows many rows for one payment", MIG,
     "CREATE UNIQUE INDEX IF NOT EXISTS point_cap_usage_payment_row_once_index",
     "CREATE INDEX IF NOT EXISTS point_cap_usage_payment_row_once_index"),
]


def env(path):
    partition = "_breaks_db" if path == MIG else "_breaks"
    return dict(os.environ, MIX_ENV="test", MIX_TEST_PARTITION=partition)


def drop_database():
    subprocess.run(
        ["mix", "run", "--no-start", "-e",
         "Ecto.Adapters.Postgres.storage_down(RegentPoints.Repo.config())"],
        cwd=ROOT, env=env(MIG), check=True, capture_output=True)


def run(path):
    out = subprocess.run(["mix", "test", *TESTS], cwd=ROOT, env=env(path),
                         capture_output=True, text=True)
    text = out.stdout + out.stderr
    result = re.findall(r"^\d+ (?:propert|tests?).*failures?.*$", text, re.M)
    red = re.findall(r"^\s+\d+\) (?:test|property) (.*) \(", text, re.M)
    return out.returncode, (result[-1] if result else "no result"), red


def main(only):
    chosen = [b for b in BREAKS if not only or b[0][:2] in only]
    missing = [name for name, path, old, _ in chosen if (ROOT / path).read_text().count(old) != 1]
    if missing:
        print("Not found exactly once, nothing run:", *missing, sep="\n  ")
        return 2

    code, result, _ = run(INT)
    print(f"unbroken: exit={code} {result}", flush=True)
    ok = code == 0
    for name, path, old, new in chosen:
        file = ROOT / path
        original = file.read_text()
        file.write_text(original.replace(old, new))
        try:
            if path == MIG:
                drop_database()
            code, result, red = run(path)
        finally:
            file.write_text(original)
            if path == MIG:
                drop_database()
        verdict = "CAUGHT" if code != 0 and result != "no result" else (
            "MISSED" if code == 0 else "DID NOT COMPILE")
        ok = ok and verdict == "CAUGHT"
        print(f"{name}: {verdict} exit={code} {result} red: {red}", flush=True)

    code, result, _ = run(INT)
    print(f"unbroken again: exit={code} {result}", flush=True)
    return 0 if ok and code == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
