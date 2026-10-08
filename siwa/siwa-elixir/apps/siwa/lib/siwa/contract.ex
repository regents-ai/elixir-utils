defmodule Siwa.Contract do
  @moduledoc """
  The signed agent request contract: the one definition every SIWA signer and
  verifier follows, an RFC 9421 signature carried in SIWA's own two headers.
  `Siwa.RequestAuth` and `Siwa.AgentAuthPlug` read it from here.

  `mix siwa.contract` writes it as `siwa/contract/contract.json`, with signed
  conformance fixtures, for signers and verifiers in other languages. Those files
  are generated copies; `mix check` fails when they differ from this definition.
  The contract id is the sha-256 of `contract.json`.

  Each covered component and signature parameter names the value it comes
  `from`: `method`, `path`, `receipt`, `key_id`, `created`, `expires`, `nonce`,
  `wallet_address` or `chain_id`. `query` says how a query string is handled and
  `refusals` what the sign-in server answers for each verifier refusal.
  """

  @version 1
  @label "sig1"
  @signature_header "x-siwa-signature"
  @signature_input_header "x-siwa-signature-input"

  @components [
    {"@method", "method"},
    {"@path", "path"},
    {"x-siwa-receipt", "receipt"},
    {"x-key-id", "key_id"},
    {"x-timestamp", "created"},
    {"x-agent-wallet-address", "wallet_address"},
    {"x-agent-chain-id", "chain_id"}
  ]

  @body_component "content-digest"
  @body_algorithm "sha-256"

  @params [
    {"created", "created"},
    {"expires", "expires"},
    {"nonce", "nonce"},
    {"keyid", "key_id"}
  ]

  @lifetime_seconds 120

  @required_headers [
    @signature_header,
    @signature_input_header
    | for({name, _from} <- @components, not String.starts_with?(name, "@"), do: name)
  ]

  # A query string is refused unless the site signs it; a signed query is part
  # of `@path`, written `path?query`. RFC 9421's `@path` never carries one.
  @query [default: :refuse, signed_in: "@path", signed_form: "path?query"]

  # What the sign-in server answers for each verifier refusal: `{reason, status,
  # code, message}`.
  @refusals [
    {:missing_signed_headers, 401, "http_headers_missing",
     "missing required signed agent headers: " <> Enum.join(@required_headers, ", ")},
    {:timestamp_mismatch, 401, "http_signature_invalid", "invalid signed request"},
    {:signature_key_id_mismatch, 401, "http_signature_invalid", "invalid signed request"},
    {:invalid_signature_input, 401, "http_signature_input_invalid",
     "invalid x-siwa-signature-input header"},
    {:request_not_yet_valid, 401, "http_signature_invalid", "signed request is not yet valid"},
    {:request_too_old, 401, "http_signature_invalid", "signed request is too old"},
    {:request_expired, 401, "http_signature_invalid", "signed request has expired"},
    {:invalid_timestamp, 401, "http_signature_invalid", "invalid x-timestamp header"},
    {:missing_covered_components, 401, "http_required_components_missing",
     "missing required covered components"},
    {:invalid_covered_components, 401, "http_signature_input_invalid",
     "invalid covered components"},
    {:request_body_required, 401, "http_body_binding_missing",
     "request body is required when content-digest is present"},
    {:missing_content_digest, 401, "http_body_binding_missing", "missing content-digest header"},
    {:content_digest_mismatch, 401, "http_body_binding_invalid",
     "content-digest does not match the request body"},
    {:invalid_content_digest, 401, "http_body_binding_invalid", "content-digest is invalid"},
    {:invalid_receipt, 401, "receipt_invalid", "invalid SIWA receipt"},
    {:receipt_audience_required, 401, "receipt_invalid", "invalid SIWA receipt"},
    {:receipt_binding_mismatch, 401, "receipt_binding_mismatch",
     "receipt audience or claims does not match this request"},
    {:chain_binding_mismatch, 401, "receipt_binding_mismatch",
     "x-agent-chain-id does not match SIWA receipt"},
    {:invalid_signature_header, 401, "http_signature_invalid", "invalid x-siwa-signature header"},
    {:signature_invalid, 401, "signature_invalid", "signature does not match wallet"},
    {:signature_lookup_failed, 502, "signature_lookup_failed",
     "could not check the wallet signature on the chain it signed in on"},
    {:replayed_request, 409, "request_replayed", "request replay detected"},
    {:wallet_principal_not_allowed, 401, "wallet_audience_disabled",
     "wallet principal is not enabled for this audience"}
  ]

  def version, do: @version
  def label, do: @label
  def signature_header, do: @signature_header
  def signature_input_header, do: @signature_input_header
  def body_component, do: @body_component
  def body_algorithm, do: @body_algorithm
  def lifetime_seconds, do: @lifetime_seconds

  @doc "Whether a site signs queries when it does not say: `:refuse`."
  def query_default, do: @query[:default]

  @doc """
  The sign-in server's `{status, code, message}` for a verifier refusal reason;
  `nil` for a reason the verifier never gives.
  """
  def refusal(reason) do
    case List.keyfind(@refusals, reason, 0) do
      {_reason, status, code, message} -> {status, code, message}
      nil -> nil
    end
  end

  @doc "The covered components in signing order, as `{name, from}`; a body adds `body_component/0` last."
  def components, do: @components

  @doc "The signature parameters in order, as `{name, from}`."
  def params, do: @params

  @doc "The covered component names, without the body component."
  def component_names, do: Enum.map(@components, &elem(&1, 0))

  @doc "The components sent as headers, as `{header, from}`."
  def header_components, do: Enum.reject(@components, &derived?/1)

  @doc "The header that carries the value from `from`."
  def header_for(from) do
    {header, ^from} = List.keyfind(header_components(), from, 1)
    header
  end

  @doc "The `from` of a covered component name; `nil` for the body component."
  def source(name) do
    case List.keyfind(@components, name, 0) do
      {^name, from} -> from
      nil -> nil
    end
  end

  @doc "The signature parameter that carries the value from `from`."
  def param_name(from) do
    {name, ^from} = List.keyfind(@params, from, 1)
    name
  end

  @doc "The headers a signed request carries without a body."
  def required_headers, do: @required_headers

  @doc """
  Every header a signed agent request may carry: the required ones plus the body
  component. A site forwards exactly these to the sign-in server and nothing else.
  """
  def forwarded_headers, do: required_headers() ++ [@body_component]

  @doc "The contract as the JSON written to `siwa/contract/contract.json`."
  def json do
    Jason.OrderedObject.new(
      version: @version,
      label: @label,
      signature_header: @signature_header,
      signature_input_header: @signature_input_header,
      components: Enum.map(@components, &named/1),
      body: Jason.OrderedObject.new(component: @body_component, algorithm: @body_algorithm),
      params: Enum.map(@params, &named/1),
      lifetime_seconds: @lifetime_seconds,
      forwarded_headers: forwarded_headers(),
      query:
        Jason.OrderedObject.new(Enum.map(@query, fn {key, value} -> {key, to_string(value)} end)),
      refusals:
        Enum.map(@refusals, fn {reason, status, code, message} ->
          Jason.OrderedObject.new(
            reason: Atom.to_string(reason),
            status: status,
            code: code,
            message: message
          )
        end)
    )
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  @doc "The contract id: the lowercase hex sha-256 of `json/0`."
  def id, do: :crypto.hash(:sha256, json()) |> Base.encode16(case: :lower)

  defp derived?({"@" <> _name, _from}), do: true
  defp derived?(_component), do: false

  defp named({name, from}), do: Jason.OrderedObject.new(name: name, from: from)
end
