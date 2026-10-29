defmodule Siwa.Contract.Fixtures do
  @moduledoc """
  Conformance fixtures for `Siwa.Contract`, written by `mix siwa.contract` as
  `siwa/contract/fixtures.json`.

  Every request is signed by test key `0x…01` with a fixed receipt secret, time
  and nonce, so the file is the same on every run. A signer in another language
  reproduces the `signed` cases byte for byte; a verifier or site refuses the
  `refused` cases with the given reason and accepts the `accepted` ones with the
  given principal.

  Request headers are `[name, value]` pairs sorted by name, so a repeated header
  can be written down. `body` is `null` when the request has none. `query` is the
  site's query setting: `"refuse"`, or `"signed"` when the query string is signed.
  `checked_by` names the first layer that refuses a case: `verifier` (the
  signature check, `Siwa.RequestAuth`), `site_plug` (`Siwa.AgentAuthPlug`, before
  the sign-in server is asked) or `siwa_server` (it needs the sign-in server's
  replay window or chain reads: a signature that is not the signer's is refused
  as `signature_invalid` only once the chain shows no smart wallet signed it). A
  case with `sends` is refused on that send, the earlier ones accepted. A case
  the sign-in server refuses carries the `status` and `code` it answers with
  (`refusals` in the contract); a `site_plug` case never reaches it.
  """

  alias Siwa.{Contract, Crypto, LocalSigner, Receipt, RequestAuth}

  @private_key "0x" <> String.duplicate("0", 63) <> "1"
  @secret "siwa-contract-fixture-secret"
  @audience "siwa-contract-fixture"
  @chain_id 8453
  @created 1_790_000_000
  @nonce "sig-nonce-fixture"
  @receipt_nonce "receipt-nonce-fixture"
  @json_body ~s({"a":1})
  @platform_signature_input ~s|sig1=("@method" "@path");created=1790000000;keyid="platform-bot"|
  @platform_signature "sig1=:" <> Base.encode64(:binary.copy(<<1>>, 64)) <> ":"

  @doc "The fixtures as the JSON written to `siwa/contract/fixtures.json`."
  def json do
    signer = signer()
    receipt = receipt(signer)
    no_body = sign(signer, receipt, "GET", "/fixture", nil)
    json_body = sign(signer, receipt, "POST", "/fixture", @json_body)
    signed_query = sign(signer, receipt, "GET", "/fixture?cursor=2", nil)

    Jason.OrderedObject.new(
      contract_id: Contract.id(),
      signer: Jason.OrderedObject.new(private_key: @private_key, address: signer.address),
      receipt:
        Jason.OrderedObject.new(secret: @secret, token: receipt.token, payload: receipt.payload),
      verify: Jason.OrderedObject.new(audience: @audience, now: @created),
      signing:
        Jason.OrderedObject.new(
          created: @created,
          expires: @created + Contract.lifetime_seconds(),
          nonce: @nonce
        ),
      principal: principal(signer),
      signed: [
        signed_case("no_body", no_body, "refuse"),
        signed_case("json_body", json_body, "refuse"),
        signed_case(
          "empty_object_body",
          sign(signer, receipt, "GET", "/fixture", "{}"),
          "refuse"
        ),
        signed_case("signed_query", signed_query, "signed")
      ],
      refused: [
        refused_case(
          "tampered_body",
          %{json_body | body: ~s({"a":2})},
          "verifier",
          :content_digest_mismatch
        ),
        refused_case("wrong_audience", no_body, "verifier", :receipt_binding_mismatch,
          audience: "another-site"
        ),
        refused_case("replay", no_body, "siwa_server", :replayed_request, sends: 2),
        refused_case(
          "repeated_proof_header",
          add_headers(no_body, [
            List.keyfind(no_body.headers, Contract.signature_header(), 0)
          ]),
          "site_plug",
          :duplicate_proof
        ),
        refused_case(
          "repeated_signature_input_header",
          add_headers(no_body, [
            List.keyfind(no_body.headers, Contract.signature_input_header(), 0)
          ]),
          "site_plug",
          :duplicate_proof
        ),
        refused_case(
          "repeated_timestamp_header",
          add_headers(no_body, [List.keyfind(no_body.headers, Contract.header_for("created"), 0)]),
          "site_plug",
          :duplicate_proof
        ),
        refused_case(
          "malformed_signature",
          put_header(no_body, Contract.signature_header(), Contract.label() <> "=:not base64:"),
          "verifier",
          :invalid_signature_header
        ),
        refused_case(
          "expired_signature",
          sign(
            signer,
            receipt,
            "GET",
            "/fixture",
            nil,
            @created - Contract.lifetime_seconds() - 1
          ),
          "verifier",
          :request_expired
        ),
        refused_case(
          "created_in_future",
          sign(signer, receipt, "GET", "/fixture", nil, @created + 301),
          "verifier",
          :request_not_yet_valid
        ),
        refused_case(
          "timestamp_differs_from_created",
          put_header(no_body, Contract.header_for("created"), Integer.to_string(@created + 1)),
          "verifier",
          :timestamp_mismatch
        ),
        refused_case(
          "malformed_signature_input",
          put_header(no_body, Contract.signature_input_header(), Contract.label() <> "=garbage"),
          "verifier",
          :invalid_signature_input
        ),
        refused_case(
          "unsigned_body",
          %{no_body | body: @json_body},
          "verifier",
          :missing_signed_headers
        ),
        refused_case(
          "unsigned_query",
          %{no_body | path: "/fixture?cursor=2"},
          "site_plug",
          :unsupported_query
        ),
        refused_case(
          "changed_query",
          %{signed_query | path: "/fixture?cursor=3"},
          "siwa_server",
          :signature_invalid,
          query: "signed"
        )
      ],
      accepted: [
        accepted_case("extra_unsigned_header", add_headers(no_body, [{"x-agent-role", "admin"}])),
        accepted_case(
          "mixed_case_header_names",
          %{
            no_body
            | headers:
                Enum.map(no_body.headers, fn {name, value} -> {title_case(name), value} end)
          }
        ),
        accepted_case(
          "platform_signature_alongside",
          add_headers(no_body, [
            {"signature", @platform_signature},
            {"signature-input", @platform_signature_input}
          ])
        )
      ]
    )
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  @doc "The options `Siwa.RequestAuth.verify_authenticated_request/2` takes for these fixtures, without a replay store."
  def verify_opts(audience \\ @audience) do
    [
      secret: @secret,
      audience: audience,
      wallet_audiences: [audience],
      now: DateTime.from_unix!(@created)
    ]
  end

  defp signer do
    {public_key, _private_key} =
      :crypto.generate_key(:ecdh, :secp256k1, Crypto.decode_hex!(@private_key))

    LocalSigner.from_private_key(@private_key, Crypto.encode_hex(public_key))
  end

  defp receipt(signer) do
    {:ok, receipt} =
      Receipt.create(
        %{
          "typ" => "siwa_wallet_receipt",
          "verified" => "wallet_signature",
          "jti" => "receipt-fixture",
          "sub" => signer.address,
          "aud" => @audience,
          "chain_id" => @chain_id,
          "nonce" => @receipt_nonce,
          "key_id" => signer.address
        },
        verify_opts()
      )

    receipt
  end

  defp sign(signer, receipt, method, path, body, created \\ @created) do
    {:ok, signed} =
      RequestAuth.sign_authenticated_request(
        %{method: method, path: path, body: body, headers: %{}},
        receipt.token,
        signer,
        Keyword.merge(verify_opts(), created_at: created, nonce: @nonce)
      )

    %{signed | headers: Enum.sort(signed.headers)}
  end

  defp principal(signer),
    do:
      Jason.OrderedObject.new(
        wallet_address: signer.address,
        chain_id: @chain_id,
        key_id: signer.address
      )

  defp signed_case(name, request, query) do
    {:ok, message} = RequestAuth.signing_message(%{request | headers: Map.new(request.headers)})

    Jason.OrderedObject.new(
      name: name,
      query: query,
      request: request_json(request),
      signing_message: message
    )
  end

  defp refused_case(name, request, checked_by, reason, opts \\ []) do
    Jason.OrderedObject.new(
      [
        name: name,
        query: Keyword.get(opts, :query, "refuse"),
        request: request_json(request),
        checked_by: checked_by,
        reason: Atom.to_string(reason)
      ] ++ server_answer(checked_by, reason) ++ Keyword.take(opts, [:audience, :sends])
    )
  end

  defp server_answer("site_plug", _reason), do: []

  defp server_answer(_checked_by, reason) do
    {status, code, _message} = Contract.refusal(reason)
    [status: status, code: code]
  end

  defp accepted_case(name, request),
    do: Jason.OrderedObject.new(name: name, query: "refuse", request: request_json(request))

  defp request_json(request) do
    Jason.OrderedObject.new(
      method: request.method,
      path: request.path,
      body: request.body,
      headers: Enum.map(request.headers, &Tuple.to_list/1)
    )
  end

  defp title_case(name),
    do: name |> String.split("-") |> Enum.map_join("-", &String.capitalize/1)

  defp add_headers(request, pairs), do: %{request | headers: Enum.sort(request.headers ++ pairs)}

  defp put_header(request, name, value),
    do: %{request | headers: Enum.sort(List.keystore(request.headers, name, 0, {name, value}))}
end
