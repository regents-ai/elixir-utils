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

  test "an agent with no extra line gets the four lines and its key's folder only" do
    lines =
      "ABCD-1234" |> PairingMessage.text("http://localhost:4000", :other) |> String.split("\n")

    assert [
             "Pair with my Regents Labs account on localhost",
             "Pairing code: ABCD-1234",
             _steps,
             "The code works once, for ten minutes. If it fails, ask me for a new one.",
             _key_home
           ] = lines
  end

  # Sean 27 Oct 2026 (AGENT-KEY-HOME a): agents sharing one computer each keep
  # their own key, so each pairs as a separate agent.
  test "every agent but ChatGPT keeps its key in its own runtime's folder, before the site's lines" do
    homes =
      for harness <- [nil | RegentAgents.Harness.values()], harness != :chatgpt do
        lines =
          "ABCD-1234"
          |> PairingMessage.text("https://keyfleet.ai", harness,
            setup: "Check in every 30 minutes.",
            start: "/classic/1"
          )
          |> String.split("\n")

        assert [home] =
                 for(
                   line <- lines,
                   [_, home] <- [Regex.run(~r/SIWA_AGENT_HOME=(\S+)$/, line)],
                   do: home
                 )

        assert Enum.find_index(lines, &(&1 =~ "SIWA_AGENT_HOME")) <
                 Enum.find_index(lines, &(&1 == "Check in every 30 minutes."))

        {harness, home}
      end

    named = for {harness, home} <- homes, harness not in [nil, :other], do: home
    assert Enum.uniq(named) == named
    assert Enum.all?(named, &(&1 =~ ~r{\A~/\.siwa-agent/[a-z][a-z-]*\z}))
    assert homes[nil] == homes[:other]
    refute homes[:other] in named

    refute PairingMessage.text("ABCD-1234", "https://patchbay.sh", :chatgpt) =~
             "SIWA_AGENT_HOME"
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
