defmodule RegentIdentity.ProfileTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  alias RegentIdentity, as: Identity
  @wallet "0x1111111111111111111111111111111111111111"
  @other_wallet "0x2222222222222222222222222222222222222222"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentIdentity.TestRepo)
    %{actor: actor("person-#{System.unique_integer([:positive])}")}
  end

  defp actor(subject, attrs \\ %{}) do
    struct!(
      RegentPrivy.Session,
      Map.merge(
        %{
          app_id: "common-app",
          privy_user_id: subject,
          session_id: "local-session",
          wallet_addresses: [@wallet],
          wallet_address: @wallet,
          issued_at: System.system_time(:second) - 10,
          expires_at: System.system_time(:second) + 3600
        },
        attrs
      )
    )
  end

  test "same verified subject resolves the same ID and identical rerun makes no change", %{
    actor: actor
  } do
    assert {:ok, first} = Identity.sync(actor)
    assert {:ok, second} = Identity.sync(%{actor | session_id: "another-site-session"})
    assert first.id == second.id
    assert first.updated_at == second.updated_at
    assert {:ok, found} = Identity.get_my_profile(actor: actor)
    assert found.id == first.id
    assert {:ok, nil} = Identity.get_my_profile(actor: %{actor | privy_user_id: "other"})
    assert {:error, _} = Identity.get_my_profile()
  end

  test "sign-in gives a person a profile once and leaves an existing one as it is", %{
    actor: actor
  } do
    assert {:ok, nil} = Identity.profile_id(actor.app_id, actor.privy_user_id)
    assert {:ok, made} = Identity.ensure(actor)
    assert {:ok, made.id} == Identity.profile_id(actor.app_id, actor.privy_user_id)

    older = %{actor | issued_at: actor.issued_at - 5, wallet_addresses: [@other_wallet]}
    assert {:ok, kept} = Identity.ensure(older)
    assert kept.id == made.id
    assert kept.wallet_addresses == [@wallet]
    assert {:ok, nil} = Identity.profile_id("another-app", actor.privy_user_id)
  end

  test "X proof is private and immutable subject owns mutable handle", %{actor: actor} do
    x = %{provider: :x, subject: "x-123", username: "old", display_name: "Name"}
    actor = %{actor | linked_socials: [x], wallet_addresses: [], wallet_address: nil}
    assert {:ok, profile} = Identity.sync(actor)
    assert Identity.present(profile).wallet == %{address: nil, verified: false}

    assert Identity.present(profile).x == %{
             username: "old",
             display_name: "Name",
             verified: true,
             source: "privy"
           }

    refute Map.has_key?(Identity.present(profile), :privy_user_id)
    refute Map.has_key?(Identity.present(profile).x, :subject)
    assert {:error, _} = Identity.sync(%{actor | privy_user_id: "intruder"})

    assert {:ok, updated} =
             Identity.sync(%{
               actor
               | issued_at: actor.issued_at + 1,
                 linked_socials: [%{x | username: "new"}]
             })

    assert updated.id == profile.id
    assert updated.x_subject == "x-123"
    assert Identity.present(updated).x.username == "new"
  end

  test "wallet choice survives linked-account ordering and becomes unverified after unlink", %{
    actor: actor
  } do
    assert {:ok, profile} = Identity.sync(actor)
    proof = %{actor | issued_at: actor.issued_at + 1, wallet_addresses: [@other_wallet, @wallet]}
    assert {:ok, refreshed} = Identity.sync(proof)
    assert refreshed.wallet_address == @wallet

    assert {:ok, selected} =
             Identity.edit_profile(refreshed, %{wallet_address: @other_wallet}, actor: proof)

    assert selected.wallet_address == @other_wallet

    assert {:error, _} =
             Identity.edit_profile(
               selected,
               %{wallet_address: "0x3333333333333333333333333333333333333333"},
               actor: proof
             )

    assert {:ok, unlinked} =
             Identity.sync(%{proof | issued_at: proof.issued_at + 1, wallet_addresses: [@wallet]})

    assert Identity.present(unlinked).wallet == %{address: @other_wallet, verified: false}
    assert profile.id == unlinked.id
  end

  test "owner checks apply to edits even with a valid different actor", %{actor: actor} do
    assert {:ok, profile} = Identity.sync(actor)

    assert {:error, _} =
             Identity.edit_profile(profile, %{display_name: "Taken"},
               actor: %{actor | privy_user_id: "other"}
             )

    assert {:ok, own} = Identity.edit_profile(profile, %{display_name: "Mine"}, actor: actor)
    assert own.display_name == "Mine"
  end

  test "stale and conflicting snapshots cannot restore removed links", %{actor: actor} do
    assert {:ok, _} = Identity.sync(actor)

    assert {:error, _} =
             Identity.sync(%{actor | wallet_addresses: []})

    newer = %{actor | issued_at: actor.issued_at + 2}
    assert {:ok, _} = Identity.sync(newer)

    assert {:error, _} =
             Identity.sync(%{actor | issued_at: actor.issued_at + 1, wallet_addresses: []})

    assert {:error, :unverified_identity} = Identity.sync(%{actor | expires_at: 0})
    assert {:ok, retained} = Identity.get_my_profile(actor: newer)
    assert retained.wallet_addresses == [@wallet]
    assert retained.proof_issued_at == newer.issued_at
  end

  test "different application subjects are never merged", %{actor: actor} do
    assert {:ok, first} = Identity.sync(actor)
    assert {:ok, second} = Identity.sync(%{actor | app_id: "legacy-other-app"})
    refute first.id == second.id
  end

  test "direct Ash refresh and stale record edits cannot bypass newer evidence", %{actor: actor} do
    assert {:ok, original} = Identity.sync(actor)

    assert {:ok, _} =
             Identity.sync(%{actor | issued_at: actor.issued_at + 2, wallet_addresses: []})

    assert {:error, _} =
             original |> Ash.Changeset.for_update(:refresh, %{}, actor: actor) |> Ash.update()

    assert {:ok, cleared} = Identity.edit_profile(original, %{wallet_address: nil}, actor: actor)
    assert {:error, _} = Identity.edit_profile(cleared, %{wallet_address: @wallet}, actor: actor)
    assert {:ok, retained} = Identity.get_my_profile(actor: actor)
    assert retained.wallet_addresses == []
    assert retained.wallet_address == nil
  end

  test "display names are bounded in bytes as well as visible characters", %{actor: actor} do
    assert {:ok, profile} = Identity.sync(actor)

    assert {:error, _} =
             Identity.edit_profile(
               profile,
               %{display_name: "a" <> String.duplicate(<<0xCC, 0x81>>, 200)},
               actor: actor
             )
  end

  # Hidden characters: controls, the line and paragraph separators, and format
  # characters, among them the marks that turn the text around them the other way,
  # zero-width spaces, the byte-order mark, the word joiner and the soft hyphen.
  @controls Enum.concat(0..31, 127..159)
  @separators [0x2028, 0x2029]
  @formats Enum.concat([
             [0x00AD, 0x061C, 0x06DD, 0x070F, 0x180E, 0xFEFF, 0x110BD, 0xE0001],
             0x0600..0x0605,
             [0x200B, 0x200E, 0x200F],
             0x202A..0x202E,
             0x2060..0x2064,
             0x2066..0x206F,
             0xFFF9..0xFFFB,
             0x1D173..0x1D17A
           ])
  @joiners [0x200C, 0x200D]
  @flag 0x1F3F4
  @tags 0xE0020..0xE007E
  @flag_end 0xE007F

  # One character from anywhere in Unicode that a name may hold on its own, and one
  # of those that also shows something (no space of any kind).
  defp plain,
    do: filter(string(:utf8, length: 1), &(not Regex.match?(~r/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u, &1)))

  defp visible, do: filter(plain(), &(not Regex.match?(~r/\p{Z}/u, &1)))
  defp joiner, do: map(member_of(@joiners), &<<&1::utf8>>)
  defp tag, do: map(member_of(Enum.concat(@tags, [@flag_end])), &<<&1::utf8>>)

  defp flag do
    map(list_of(member_of(@tags), min_length: 1, max_length: 5), fn tags ->
      <<@flag::utf8>> <> List.to_string(tags) <> <<@flag_end::utf8>>
    end)
  end

  # A hidden character inside a name (a tab or line end at either end is trimmed
  # away before saving), a joiner beside no visible character, or a tag character
  # outside a complete flag.
  defp hidden_name do
    around = string(:printable, max_length: 30)
    hidden = map(member_of(Enum.concat([@controls, @separators, @formats])), &<<&1::utf8>>)

    one_of([
      map({around, hidden, around}, fn {before, mark, after_it} ->
        before <> "a" <> mark <> "b" <> after_it
      end),
      map({joiner(), around}, fn {mark, after_it} -> mark <> "b" <> after_it end),
      map({around, joiner()}, fn {before, mark} -> before <> "a" <> mark end),
      map({around, joiner(), around}, fn {before, mark, after_it} ->
        before <> "a " <> mark <> "b" <> after_it
      end),
      map({around, joiner(), around}, fn {before, mark, after_it} ->
        before <> "a" <> mark <> mark <> "b" <> after_it
      end),
      map({around, tag(), around}, fn {before, mark, after_it} ->
        before <> "a" <> mark <> "b" <> after_it
      end),
      map({around, list_of(member_of(@tags), min_length: 1, max_length: 5)}, fn {before, tags} ->
        before <> <<@flag::utf8>> <> List.to_string(tags) <> "b"
      end)
    ])
  end

  # Invariant: a name shows on every Regent site, so one holding a hidden
  # character is never saved (founder, 2026-10-19).
  property "a name holding a hidden character is never saved", %{actor: actor} do
    assert {:ok, profile} = Identity.sync(actor)

    check all(name <- hidden_name()) do
      assert {:error, _} = Identity.edit_profile(profile, %{display_name: name}, actor: actor)
    end
  end

  # Invariant: every other name of up to 80 characters saves as the person typed
  # it, trimmed, in any script: any character from all of Unicode but a hidden one,
  # a joiner between two visible characters, and complete flags.
  property "any other name saves as typed", %{actor: actor} do
    assert {:ok, profile} = Identity.sync(actor)

    part =
      one_of([
        plain(),
        map({visible(), joiner(), visible()}, fn {left, mark, right} -> left <> mark <> right end),
        flag()
      ])

    # A part holds at most seven characters (a flag), so eleven stay within 80.
    check all(parts <- list_of(part, max_length: 11)) do
      name = Enum.join(parts)
      assert {:ok, saved} = Identity.edit_profile(profile, %{display_name: name}, actor: actor)
      assert saved.display_name == if(String.trim(name) == "", do: nil, else: String.trim(name))
    end
  end

  test "a direct refresh from an old record applies every field of newer proof", %{actor: actor} do
    assert {:ok, original} = Identity.sync(actor)
    x = %{provider: :x, subject: "x-new", username: "new", display_name: nil}

    assert {:ok, _} =
             Identity.sync(%{
               actor
               | issued_at: actor.issued_at + 1,
                 wallet_addresses: [@other_wallet],
                 linked_socials: [x]
             })

    latest = %{actor | issued_at: actor.issued_at + 2}

    assert {:ok, _} =
             original |> Ash.Changeset.for_update(:refresh, %{}, actor: latest) |> Ash.update()

    assert {:ok, stored} = Identity.get_my_profile(actor: latest)
    assert stored.wallet_addresses == [@wallet]
    assert stored.x_subject == nil
    assert stored.proof_issued_at == latest.issued_at
  end
end
