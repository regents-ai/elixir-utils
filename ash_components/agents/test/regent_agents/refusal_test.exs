defmodule RegentAgents.RefusalTest do
  # Sean EU-REFUSAL-TESTS a: every site tells a refused agent what this says.
  use ExUnit.Case, async: true

  alias RegentAgents.Refusal

  @hint "Sign in to this site, then send the request again."
  @unreachable {503,
                %{
                  code: "siwa_request_failed",
                  message: "The sign-in service could not be reached.",
                  hint: "Try again in a moment."
                }}
  @unverified {401,
               %{
                 code: "verification_failed",
                 message: "The signed agent request could not be verified.",
                 hint: @hint
               }}

  test "the SIWA service's own refusal is passed on as the service wrote it" do
    for status <- [409, 503] do
      refusal = %{
        reason: :"siwa_http_#{status}",
        source: :siwa_http,
        siwa_status: status,
        siwa_code: "request_replayed",
        siwa_message: "This signed request was already used.",
        siwa_hint: "Sign a fresh request, then send it again."
      }

      assert Refusal.describe(refusal, @hint) ==
               {status,
                %{
                  code: "request_replayed",
                  message: "This signed request was already used.",
                  hint: "Sign a fresh request, then send it again."
                }}
    end
  end

  test "a service that failed without saying why, or was not reached, is siwa_request_failed" do
    assert Refusal.describe(
             %{reason: :siwa_http_500, source: :siwa_http, siwa_status: 500},
             @hint
           ) ==
             @unreachable

    assert Refusal.describe(%{siwa_status: 502, siwa_code: "bad_gateway"}, @hint) == @unreachable

    assert Refusal.describe(
             %{reason: :siwa_request_failed, source: :siwa_http, transport_error: :econnrefused},
             @hint
           ) == @unreachable
  end

  test "the shared plug's own refusals keep its reason as the code, with the site's hint" do
    for {reason, message} <- [
          duplicate_proof: "A signature header was sent more than once.",
          unsupported_query: "A signed request here takes no query string.",
          missing_signed_body: "Send the body as JSON, signed with the rest of the request."
        ] do
      assert Refusal.describe(%{reason: reason, source: :siwa_plug}, @hint) ==
               {401, %{code: Atom.to_string(reason), message: message, hint: @hint}}
    end
  end

  test "a service refusal below 500 without its own words is verification_failed, its status not passed on" do
    assert Refusal.describe(
             %{reason: :siwa_http_429, source: :siwa_http, siwa_status: 429},
             @hint
           ) ==
             @unverified

    assert Refusal.describe(
             %{siwa_status: 401, siwa_code: "receipt_invalid", siwa_message: "No hint came."},
             @hint
           ) == @unverified
  end

  test "any other refusal is verification_failed with the site's hint" do
    assert Refusal.describe(%{reason: :invalid_principal, source: :regent_agents}, @hint) ==
             @unverified

    assert Refusal.describe(%{reason: :not_a_plug_reason, source: :siwa_plug}, @hint) ==
             @unverified
  end
end
