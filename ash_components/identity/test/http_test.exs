defmodule RegentIdentity.HTTPTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias RegentIdentity.{HTTP, Owner}

  @wallet "0x1111111111111111111111111111111111111111"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentIdentity.TestRepo)
    %{session: session("http-#{System.unique_integer([:positive])}")}
  end

  # The sign-in the site verified, which made the person's profile.
  defp session(subject) do
    now = System.system_time(:second)

    %RegentPrivy.Session{
      app_id: "shared-app",
      privy_user_id: subject,
      session_id: "session",
      wallet_addresses: [@wallet],
      wallet_address: @wallet,
      linked_socials: [%{provider: :x, subject: subject, username: "verified_x"}],
      issued_at: now - 1,
      expires_at: now + 600
    }
  end

  # A request the site has already resolved to `owner`.
  defp request(method, path, owner, body \\ nil) do
    conn(method, path, if(body, do: Jason.encode!(body), else: nil))
    |> put_req_header("content-type", "application/json")
    |> HTTP.put_owner(owner)
    |> HTTP.call(HTTP.init([]))
  end

  defp profile(response), do: Jason.decode!(response.resp_body)["profile"]

  test "the owner the site put on the request reads and changes their own profile", %{
    session: session
  } do
    owner = Owner.of(session)
    assert request(:get, "/", owner).status == 404
    assert {:ok, _profile} = RegentIdentity.ensure(session)

    read = request(:get, "/", owner)
    assert read.status == 200
    assert get_resp_header(read, "cache-control") == ["no-store"]
    assert profile(read)["x"]["verified"] == true
    refute Map.has_key?(profile(read), "privy_user_id")
    refute Map.has_key?(profile(read)["x"], "subject")

    edited = request(:patch, "/", owner, %{display_name: "My name"})
    assert edited.status == 200
    assert profile(edited)["display_name"] == "My name"
    assert profile(request(:get, "/", owner)) == profile(edited)

    rejected = request(:patch, "/", owner, %{x_subject: "fake"})
    assert rejected.status == 422

    assert %{"code" => "invalid_profile_update", "message" => _, "hint" => _} =
             Jason.decode!(rejected.resp_body)["error"]

    assert request(:patch, "/", owner, %{profile_id: "other"}).status == 422
  end

  test "an owner reads and changes only their own profile", %{session: session} do
    other = session("http-other-#{System.unique_integer([:positive])}")
    assert {:ok, _profile} = RegentIdentity.ensure(session)
    assert {:ok, _profile} = RegentIdentity.ensure(other)

    assert request(:patch, "/", Owner.of(session), %{display_name: "Ada"}).status == 200
    assert profile(request(:get, "/", Owner.of(other)))["display_name"] == nil
    assert profile(request(:get, "/", Owner.of(session)))["display_name"] == "Ada"

    # The same person in another Privy app is someone else.
    elsewhere = %Owner{app_id: "another-app", privy_user_id: session.privy_user_id}
    assert request(:get, "/", elsewhere).status == 404
  end

  # Invariant: a name that would hide characters or turn the text around it
  # (founder, 2026-10-19) is refused with its own code, and the saved name stays.
  test "a name with a hidden character is refused", %{session: session} do
    owner = Owner.of(session)
    assert {:ok, _profile} = RegentIdentity.ensure(session)
    assert request(:patch, "/", owner, %{display_name: "Ada"}).status == 200

    for name <- [
          "Ada\u202Egnp.exe",
          "Ada\u2066Lovelace",
          "Ada\u200FL",
          "Ada\nLovelace",
          "Ada\u0000",
          "Ada\u2028L",
          "Ada\u2029L",
          "Ada\u200B",
          "Ada\uFEFF",
          "Ada\u2060",
          "Ada\u00AD",
          "Ada\u200D",
          "Ada\u{E0041}",
          # Six a looser rule once let through (Sentinel's read, 19 Oct).
          "Ada\u{E0067}\u{E0062}\u{E007F}",
          "A\u200Bda",
          "Ada\u200D Lovelace",
          "Ada \u{1F3F4}\u{E0067}\u{E0001}\u{E0062}\u{E007F}",
          "Ada \u{1F3F4}\u{E0067}\u{E007F}\u{E0062}\u{E007F}",
          "Ada \u{1F3F4}\u{E0067}\u{E0062}\u{E007F}\u200Db"
        ] do
      refused = request(:patch, "/", owner, %{display_name: name})
      assert refused.status == 422
      assert Jason.decode!(refused.resp_body)["error"]["code"] == "invalid_display_name"
    end

    assert profile(request(:get, "/", owner))["display_name"] == "Ada"

    # Emoji joined by a zero-width joiner, a flag drawn with tag characters, Persian
    # with a zero-width non-joiner, accents and right-to-left letters stay allowed.
    for name <- [
          "Ada 👩\u200D💻",
          "Ada \u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
          "می\u200Cخواهم",
          "Zoë",
          "عائشة"
        ] do
      saved = request(:patch, "/", owner, %{display_name: name})
      assert profile(saved)["display_name"] == name
    end
  end

  test "with no owner on the request nothing is read or changed", %{session: session} do
    assert {:ok, _profile} = RegentIdentity.ensure(session)

    for {method, body} <- [{:get, nil}, {:patch, Jason.encode!(%{display_name: "Mallory"})}] do
      refused =
        conn(method, "/", body)
        |> put_req_header("content-type", "application/json")
        |> HTTP.call(HTTP.init([]))

      assert refused.status == 401

      # Every refusal says what went wrong and what to do next.
      assert %{"code" => "authentication_required", "message" => _, "hint" => _} =
               Jason.decode!(refused.resp_body)["error"]
    end

    assert profile(request(:get, "/", Owner.of(session)))["display_name"] == nil
  end

  test "an edit from a previously displayed account cannot change the new account", %{
    session: session
  } do
    owner = Owner.of(session)
    assert {:ok, _profile} = RegentIdentity.ensure(session)

    response =
      conn(:patch, "/", Jason.encode!(%{display_name: "Wrong account's draft"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-regent-profile-id", Ash.UUID.generate())
      |> HTTP.put_owner(owner)
      |> HTTP.call(HTTP.init([]))

    assert response.status == 422
    assert profile(request(:get, "/", owner))["display_name"] == nil
  end

  test "an upstream form parser cannot turn a form into a JSON edit", %{session: session} do
    owner = Owner.of(session)
    assert {:ok, _profile} = RegentIdentity.ensure(session)

    response =
      conn(:patch, "/", "display_name=Forged")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:urlencoded]))
      |> HTTP.put_owner(owner)
      |> HTTP.call(HTTP.init([]))

    assert response.status == 415
    assert profile(request(:get, "/", owner))["display_name"] == nil
  end
end
