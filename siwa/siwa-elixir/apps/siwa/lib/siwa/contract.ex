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
  `wallet_address` or `chain_id`.
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

  def version, do: @version
  def label, do: @label
  def signature_header, do: @signature_header
  def signature_input_header, do: @signature_input_header
  def body_component, do: @body_component
  def body_algorithm, do: @body_algorithm
  def lifetime_seconds, do: @lifetime_seconds

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
  def required_headers,
    do: [@signature_header, @signature_input_header | Enum.map(header_components(), &elem(&1, 0))]

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
      forwarded_headers: forwarded_headers()
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
