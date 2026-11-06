defmodule RegentAgents.PairingMessageTest do
  # Sean 19 Oct 2026: agents learn the account is the person's Regents Labs
  # account and which site they pair it on. Sean 6 Nov 2026 (13 a): the message
  # is three lines, and the agent's skill holds the rest.
  use ExUnit.Case, async: true

  alias RegentAgents.{Harness, PairingMessage}

  test "every agent but the hosted runtimes gets the account, the code and its own skill" do
    for harness <- [nil | Harness.values()], harness not in Harness.hosted_runtimes() do
      lines =
        "ABCD-1234" |> PairingMessage.text("https://techtree.sh", harness) |> String.split("\n")

      assert [account, code, steps] = lines
      assert account =~ ~r/Regents Labs account on techtree\.sh\z/
      assert code =~ ~r/ABCD-1234\z/
      assert [url] = Regex.run(~r{https://\S+\z}, steps)
      assert url == PairingMessage.skill_url("https://techtree.sh", harness)
    end
  end

  test "an agent's skill is its harness's page, and any agent's is other's" do
    assert PairingMessage.skill_url("https://keyfleet.ai", :grok_bot) ==
             "https://keyfleet.ai/agents/grok-bot/skill.md"

    assert PairingMessage.skill_url("https://keyfleet.ai", nil) ==
             PairingMessage.skill_url("https://keyfleet.ai", :other)

    urls = for harness <- Harness.values(), do: PairingMessage.skill_url("https://x.sh", harness)
    assert Enum.uniq(urls) == urls
  end

  test "a pairing link's page is where the agent starts once paired" do
    for harness <- [:codex, :other, :chatgpt, :claude] do
      message =
        PairingMessage.text("ABCD-1234", "https://keyfleet.ai", harness, start: "/classic/1")

      assert message =~ ~r/\nOnce paired, start at https:\/\/keyfleet.ai\/classic\/1\z/
      refute PairingMessage.text("ABCD-1234", "https://keyfleet.ai", harness) =~ "Once paired"
    end
  end

  test "ChatGPT connects to the Regents Labs account on the site's host" do
    message = PairingMessage.text("ABCD-1234", "https://patchbay.sh", :chatgpt)

    assert message =~
             ~r/\AConnect ChatGPT to my existing Regents Labs account on patchbay.sh using/

    assert message =~ "My Agents page is https://patchbay.sh/account/agents#account-pairing."
  end

  test "Claude connects through the site's connector and pairs as the claude harness" do
    message = PairingMessage.text("ABCD-1234", "https://keyfleet.ai", :claude)

    assert message =~
             ~r/\AConnect Claude to my existing Regents Labs account on keyfleet.ai using this site's connector\.\n/

    assert message =~
             "pair_identity with this one-use code, the name Claude and the harness claude."

    assert message =~ "Pairing code: ABCD-1234\n"
    assert message =~ "If the connector's identity tools are unavailable"
  end
end
