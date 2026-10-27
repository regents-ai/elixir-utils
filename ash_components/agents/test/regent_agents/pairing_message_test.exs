defmodule RegentAgents.PairingMessageTest do
  # Sean 19 Oct 2026: agents learn the account is the person's Regents Labs
  # account and which site they pair it on.
  use ExUnit.Case, async: true

  alias RegentAgents.PairingMessage

  test "the message names the Regents Labs account and the site's host" do
    message = PairingMessage.text("ABCD-1234", "https://techtree.sh", :muse)

    assert message =~ ~r/\APair with my Regents Labs account on techtree.sh\n/
    assert message =~ "Pairing code: ABCD-1234\n"
    assert message =~ "steps at https://techtree.sh/llms.txt\n"
    assert message =~ "SIWA_BROKER=https://siwa-server.fly.dev"
  end

  test "an agent with no extra line gets the four lines only" do
    lines =
      "ABCD-1234" |> PairingMessage.text("http://localhost:4000", :other) |> String.split("\n")

    assert [
             "Pair with my Regents Labs account on localhost",
             "Pairing code: ABCD-1234",
             _steps,
             "The code works once, for ten minutes. If it fails, ask me for a new one."
           ] = lines
  end

  test "a pairing link's page is where the agent starts once paired" do
    for harness <- [:codex, :other, :chatgpt] do
      message =
        PairingMessage.text("ABCD-1234", "https://keyfleet.ai", harness, start: "/classic/1")

      assert message =~ ~r/\nOnce paired, start at https:\/\/keyfleet.ai\/classic\/1\z/
      refute PairingMessage.text("ABCD-1234", "https://keyfleet.ai", harness) =~ "Once paired"
    end
  end

  test "the site's own lines come after the pairing lines and before the start line" do
    for harness <- [:muse, :other, :chatgpt] do
      lines =
        "ABCD-1234"
        |> PairingMessage.text("https://keyfleet.ai", harness,
          setup: "Check in every 30 minutes.\nYour full setup: https://keyfleet.ai/agents/x",
          start: "/classic/1"
        )
        |> String.split("\n")

      assert [
               "Check in every 30 minutes.",
               "Your full setup: " <> _,
               "Once paired, start at " <> _
             ] =
               Enum.take(lines, -3)

      assert lines -- Enum.take(lines, -3) ==
               String.split(
                 PairingMessage.text("ABCD-1234", "https://keyfleet.ai", harness),
                 "\n"
               )
    end
  end

  test "ChatGPT connects to the Regents Labs account on the site's host" do
    message = PairingMessage.text("ABCD-1234", "https://patchbay.sh", :chatgpt)

    assert message =~
             ~r/\AConnect ChatGPT to my existing Regents Labs account on patchbay.sh using/

    assert message =~ "My account page is https://patchbay.sh/account."
  end
end
