defmodule Siwa do
  @moduledoc "Main public entry points for the Elixir SIWA port."

  alias Siwa.{Message, Nonce, Receipt, RequestAuth, Verify}

  defdelegate build_message(fields), to: Message, as: :build
  defdelegate parse_message(message), to: Message, as: :parse
  defdelegate create_nonce(params, opts \\ []), to: Nonce, as: :issue
  defdelegate verify_nonce(params, opts \\ []), to: Nonce, as: :consume
  defdelegate create_nonce_token(payload, opts \\ []), to: Nonce
  defdelegate verify_nonce_token(token, opts \\ []), to: Nonce
  defdelegate sign_message(fields, signer), to: Verify, as: :sign_message
  defdelegate verify(message, signature, opts \\ []), to: Verify
  defdelegate create_receipt(payload, opts \\ []), to: Receipt, as: :create
  defdelegate verify_receipt(token, opts \\ []), to: Receipt, as: :verify
  defdelegate sign_authenticated_request(request, receipt, signer, opts \\ []), to: RequestAuth
  defdelegate verify_authenticated_request(request, opts \\ []), to: RequestAuth
end
