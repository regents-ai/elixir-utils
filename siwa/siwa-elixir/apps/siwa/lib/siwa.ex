defmodule Siwa do
  @moduledoc """
  Main public entry points: wallet sign-in receipts and the signed requests that
  carry them.
  """

  alias Siwa.{Contract, Receipt, RequestAuth}

  defdelegate create_receipt(payload, opts \\ []), to: Receipt, as: :create
  defdelegate verify_receipt(token, opts \\ []), to: Receipt, as: :verify
  defdelegate sign_authenticated_request(request, receipt, signer, opts \\ []), to: RequestAuth
  defdelegate verify_authenticated_request(request, opts \\ []), to: RequestAuth
  defdelegate content_digest_for_body(body), to: RequestAuth
  defdelegate forwarded_headers(), to: Contract

  defdelegate required_authenticated_request_headers(body),
    to: RequestAuth,
    as: :required_headers

  defdelegate required_authenticated_request_components(headers, body),
    to: RequestAuth,
    as: :required_covered_components
end
