defmodule RegentOAuth.Refusal do
  @moduledoc """
  Why a request was refused, said without any value from it.

  Each check that refuses names a reason atom. A JSON answer carries a fixed
  `error_description` for it, and one warning names the endpoint and the
  reason, as `oauth refused endpoint=token reason=resource`; a refusal page or
  redirect keeps only the warning. A code or refresh token that fails, and a
  client that fails authentication, is answered with one description whatever
  the reason, so the answer never says why a credential failed: only the
  warning does. A refusal Boruta made is
  logged by Boruta's own error name, which no reason here shares.
  """
  require Logger

  @descriptions %{
    body: "The request body could not be read.",
    unexpected_parameter: "Unexpected parameter.",
    too_large: "The request is too large.",
    disabled: "OAuth is not enabled on this server.",
    resource: "The resource parameter must be this server's resource.",
    scope: "The scope is not one this server offers.",
    response_type: "Unsupported response_type.",
    code_challenge_method: "PKCE with S256 is required.",
    code_challenge: "The code_challenge must be an S256 challenge.",
    state: "A state parameter is required.",
    grant_type: "Unsupported grant_type.",
    client_id: "Unknown client_id.",
    no_client: "The request does not name its client.",
    assertion_subject: "The client_assertion does not name a client.",
    unavailable: "The client's keys could not be read just now.",
    client_id_address: "The client_id is not a valid client address.",
    client_not_public: "Only public clients using PKCE can connect.",
    redirect_uri: "The redirect_uri is not registered for this client.",
    inactive_subject: "The signed-in account is not active.",
    decision: "The decision must be allow or deny.",
    token: "The token parameter is missing or too long.",
    token_endpoint_auth_method: "The token_endpoint_auth_method must be none.",
    response_types: "The response_types must be code.",
    grant_types: "The grant_types must be authorization_code and refresh_token.",
    client_name: "The client_name must be 1 to 100 characters.",
    redirect_uris: "One to five redirect_uris are required.",
    redirect_uri_format: "A redirect_uri is not an address this server accepts.",
    client_not_saved: "The client could not be registered.",
    document_unreadable: "The client's document could not be read.",
    document_status: "The client's document address did not answer with a document.",
    document_type: "The client's document is not JSON.",
    document_json: "The client's document is not a JSON object.",
    document_client_id: "The client's document names a different client_id.",
    document_secret: "The client's document must not carry a client secret.",
    document_auth_method:
      "The client's document must use token_endpoint_auth_method none or private_key_jwt.",
    document_jwks: "The client's document must not carry its keys inline.",
    document_jwks_uri: "The client's document has no HTTPS jwks_uri on its own host.",
    document_signing_alg:
      "The client's document names a signing algorithm other than RS256 or ES256.",
    document_grant_types: "The client's document must allow the authorization_code grant.",
    document_response_types: "The client's document must allow the code response type.",
    document_redirect_uris: "The client's document must list one to ten redirect_uris.",
    document_callbacks: "The client's document has no HTTPS redirect_uri on its own host.",
    document_client_name: "The client's document has a client_name that is not valid.",
    document_not_saved: "The client's document could not be recorded.",
    # Answer codes, for refusals whose reason stays out of the answer.
    invalid_grant: "The code or refresh token is not valid.",
    invalid_request: "A parameter is missing or not valid.",
    invalid_client: "The client is not valid for this request.",
    invalid_scope: "The scope is not one this server offers.",
    unsupported_grant_type: "Unsupported grant_type.",
    unauthorized_client: "This client may not use this grant_type.",
    unexpected: "The request could not be completed."
  }

  @doc "`:ok` when a check passed, otherwise `{:error, reason}`."
  def check(true, _reason), do: :ok
  def check(_failed, reason), do: {:error, reason}

  @doc "Logs one refusal: the endpoint and the reason, never a value."
  def log(endpoint, reason) when is_atom(endpoint) and is_atom(reason),
    do: Logger.warning("oauth refused endpoint=#{endpoint} reason=#{reason}")

  @doc "Logs the refusal and answers `error` as JSON, described by its reason."
  def answer(conn, endpoint, status, error, reason),
    do: answer(conn, endpoint, status, error, reason, reason)

  @doc """
  Logs the refusal by `reason` and answers `error` as JSON with the description
  of `described`, for a refusal whose reason the answer must not say.
  """
  def answer(conn, endpoint, status, error, reason, described) do
    log(endpoint, reason)

    RegentOAuth.Protocol.json(conn, status, %{
      error: error,
      error_description: Map.fetch!(@descriptions, described)
    })
  end
end
