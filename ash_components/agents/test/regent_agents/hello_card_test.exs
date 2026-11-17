defmodule RegentAgents.HelloCardTest do
  # The published keys are kept for the whole node, so these tests run one at a
  # time, each starting with none kept.
  use RegentAgents.Case, async: false

  import Plug.Test

  alias RegentAgents.HelloCard

  @wallet "0x2222222222222222222222222222222222222222"
  @subject "eip155:8453:" <> @wallet
  @other_subject "eip155:8453:0x3333333333333333333333333333333333333333"
  @card "siwa-hello-card+jws"
  @service "siwa-service+jwt"

  setup do
    :persistent_term.erase({HelloCard, :keys})
    key = new_key()
    siwa([key.jwk])
    %{key: key}
  end

  # An Ed25519 key as the SIWA service publishes it, `kid` its RFC 7638 thumbprint.
  defp new_key do
    {public, seed} = :crypto.generate_key(:eddsa, :ed25519)
    x = encode(public)
    kid = encode(:crypto.hash(:sha256, ~s({"crv":"Ed25519","kty":"OKP","x":"#{x}"})))

    %{
      seed: seed,
      jwk: %{
        "kty" => "OKP",
        "crv" => "Ed25519",
        "alg" => "EdDSA",
        "use" => "sig",
        "kid" => kid,
        "x" => x
      }
    }
  end

  defp sign(key, typ, claims, kid \\ nil) do
    header =
      encode(Jason.encode!(%{"alg" => "EdDSA", "typ" => typ, "kid" => kid || key.jwk["kid"]}))

    payload = encode(Jason.encode!(claims))
    signature = :crypto.sign(:eddsa, :none, header <> "." <> payload, [key.seed, :ed25519])
    Enum.join([header, payload, encode(signature)], ".")
  end

  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)

  defp iso(time), do: time |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  # The SIWA service: the keys it publishes, and its verdict that @wallet signed
  # a request for this site.
  defp siwa(jwks) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      case conn.request_path do
        "/.well-known/jwks.json" ->
          send(self(), :keys_read)
          Req.Test.json(conn, %{"keys" => jwks})

        "/api/shared/siwa/http-verify" ->
          Req.Test.json(conn, %{
            "code" => "http_envelope_valid",
            "data" => %{
              "verified" => true,
              "principal" => %{
                "kind" => "wallet",
                "wallet_address" => @wallet,
                "chain_id" => 8453,
                "audience" => "test"
              },
              "agentRegistration" => nil,
              "agentBook" => nil
            }
          })
      end
    end)
  end

  defp token_claims(claims \\ %{}) do
    now = System.os_time(:second)

    Map.merge(
      %{
        "iss" => "https://siwa.test",
        "aud" => "https://site.test",
        "sub" => @subject,
        "iat" => now,
        "exp" => now + 60,
        "jti" => encode(:crypto.strong_rand_bytes(16))
      },
      claims
    )
  end

  defp card_claims(fields \\ %{}) do
    now = DateTime.utc_now()

    Map.merge(
      %{
        "cardId" => encode(:crypto.strong_rand_bytes(16)),
        "subject" => @subject,
        "name" => "Sol",
        "person" => "Ada",
        "pairedAt" => iso(DateTime.add(now, -7, :day)),
        "pairedOn" => "keyfleet",
        "issuedAt" => iso(now),
        "expiresAt" => iso(DateTime.add(now, 1, :day))
      },
      fields
    )
  end

  defp pair!(name, owner, wallet \\ @wallet) do
    RegentAgents.pair_agent!(code!(person(owner)), name, :codex,
      actor: %RegentAgents.Agent{wallet: wallet}
    )
  end

  # The SIWA service asks whether an agent is paired here.
  defp ask(token, body) do
    conn =
      conn(:post, "/api/agents/v1/pairing", Jason.encode!(body))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    conn =
      if token,
        do: Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token),
        else: conn

    conn = RegentAgents.Test.Router.call(conn, RegentAgents.Test.Router.init([]))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  # A signed agent request from @wallet, showing `card` when there is one.
  defp whoami(card) do
    conn = conn(:get, "/api/agents/v1/whoami")
    conn = if card, do: Plug.Conn.put_req_header(conn, "x-siwa-hello-card", card), else: conn
    RegentAgents.Test.Router.call(conn, RegentAgents.Test.Router.init([]))
  end

  describe "the pairing read" do
    test "answers a paired agent's name, its person as this site names them, and when it paired, and nothing else",
         %{key: key} do
      paired = pair!("Sol", "ada")

      assert {200, answer} = ask(sign(key, @service, token_claims()), %{"subject" => @subject})
      assert answer == %{"name" => "Sol", "person" => "Ada", "pairedAt" => iso(paired.paired_at)}
      refute Jason.encode!(answer) =~ "did:privy"
    end

    test "says an agent is not paired here when it has no pairing, its person cannot be named here, or it is on another chain",
         %{key: key} do
      assert {404, %{"error" => %{"code" => "not_paired_here"}}} =
               ask(sign(key, @service, token_claims()), %{"subject" => @subject})

      pair!("Away", "away")

      assert {404, %{"error" => %{"code" => "not_paired_here"}}} =
               ask(sign(key, @service, token_claims()), %{"subject" => @subject})

      on_ethereum = "eip155:1:" <> @wallet

      assert {404, %{"error" => %{"code" => "not_paired_here"}}} =
               ask(sign(key, @service, token_claims(%{"sub" => on_ethereum})), %{
                 "subject" => on_ethereum
               })
    end

    test "refuses every token the SIWA service did not sign for this site and this subject",
         %{key: key} do
      pair!("Sol", "ada")
      unpublished = new_key()
      now = System.os_time(:second)

      refused = [
        nil,
        sign(key, @card, token_claims()),
        sign(key, @card, card_claims()),
        sign(key, "JWT", token_claims()),
        sign(key, @service, token_claims(%{"iss" => "https://siwa.example"})),
        sign(key, @service, token_claims(%{"aud" => "https://other.test"})),
        sign(key, @service, token_claims(%{"iat" => now - 120, "exp" => now - 60})),
        sign(key, @service, token_claims(%{"exp" => now})),
        sign(key, @service, token_claims(%{"sub" => @other_subject})),
        sign(unpublished, @service, token_claims(), key.jwk["kid"]),
        sign(unpublished, @service, token_claims())
      ]

      for token <- refused do
        assert {401, %{"error" => %{"code" => "service_token_invalid"}}} =
                 ask(token, %{"subject" => @subject})
      end

      token = sign(key, @service, token_claims())

      for body <- [%{"subject" => @subject, "pairedOn" => "test"}, %{}, [@subject]] do
        assert {401, %{"error" => %{"code" => "service_token_invalid"}}} = ask(token, body)
      end
    end
  end

  describe "a card" do
    test "passes only for the agent that signed the request beside it, only until it expires, and only as a card",
         %{key: key} do
      now = DateTime.utc_now()
      claims = card_claims()
      card = sign(key, @card, claims)

      assert {:ok, ^claims} = HelloCard.verify(card, @subject, now)
      assert :error = HelloCard.verify(card, @other_subject, now)

      {:ok, expires_at, 0} = DateTime.from_iso8601(claims["expiresAt"])
      assert :error = HelloCard.verify(card, @subject, expires_at)

      refused = [
        sign(key, @service, claims),
        sign(key, @service, token_claims()),
        sign(key, @card, Map.put(claims, "trusted", "yes")),
        sign(key, @card, Map.delete(claims, "person")),
        sign(key, @card, %{
          claims
          | "expiresAt" => DateTime.to_iso8601(DateTime.add(now, 1, :day))
        }),
        sign(key, @card, %{claims | "person" => ""}),
        sign(new_key(), @card, claims, key.jwk["kid"]),
        sign(new_key(), @card, claims)
      ]

      for card <- refused, do: assert(:error = HelloCard.verify(card, @subject, now))
    end

    test "on a signed request is put on the request when it passes, and is nil when absent or when it does not",
         %{key: key} do
      card = sign(key, @card, card_claims())
      conn = whoami(card)
      assert conn.status == 200
      assert %{"subject" => @subject, "person" => "Ada"} = conn.assigns.hello_card
      assert_received :keys_read

      expired = DateTime.add(DateTime.utc_now(), -1, :second)

      for other <- [
            sign(key, @card, card_claims(%{"subject" => @other_subject})),
            sign(
              key,
              @card,
              card_claims(%{
                "issuedAt" => iso(DateTime.add(expired, -1, :day)),
                "expiresAt" => iso(expired)
              })
            )
          ] do
        conn = whoami(other)
        assert conn.status == 200
        assert conn.assigns.hello_card == nil
      end

      conn = whoami(nil)
      assert conn.status == 200
      assert conn.assigns.hello_card == nil
      refute_received :keys_read
    end
  end

  test "the published keys are read once an hour, and again early, at most once a minute, for a key not yet among them",
       %{key: key} do
    now = DateTime.utc_now()
    card = sign(key, @card, card_claims())

    assert {:ok, _card} = HelloCard.verify(card, @subject, now)
    assert_received :keys_read
    assert {:ok, _card} = HelloCard.verify(card, @subject, DateTime.add(now, 3_599))
    refute_received :keys_read
    assert {:ok, _card} = HelloCard.verify(card, @subject, DateTime.add(now, 3_600))
    assert_received :keys_read

    newer = new_key()
    siwa([key.jwk, newer.jwk])
    newer_card = sign(newer, @card, card_claims())

    assert :error = HelloCard.verify(newer_card, @subject, DateTime.add(now, 3_659))
    refute_received :keys_read
    assert {:ok, _card} = HelloCard.verify(newer_card, @subject, DateTime.add(now, 3_660))
    assert_received :keys_read
    assert {:ok, _card} = HelloCard.verify(newer_card, @subject, DateTime.add(now, 3_661))
    refute_received :keys_read
  end
end
