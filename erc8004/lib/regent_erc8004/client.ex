defmodule RegentERC8004.Client do
  @moduledoc """
  Bounded, read-only server client for the Agent0-style ERC-8004 subgraph schema.
  Configure an HTTPS endpoint per registry. Never accept endpoints or headers from
  URL/form parameters. The indexer's reported protocol binding is checked too;
  neither that report nor operator configuration is an on-chain proof.
  """
  alias RegentERC8004.{Ref, Snapshot}
  @derive {Inspect, only: [:registry]}
  @enforce_keys [:registry, :endpoint]
  defstruct [:registry, :endpoint, headers: []]

  @query """
  query RegentAgent($id: ID!, $agent: String!, $chain: ID!, $first: Int!, $feedbackSkip: Int!, $validationSkip: Int!) {
    protocol(id: $chain) { chainId identityRegistry }
    agent(id: $id) {
      chainId agentId owner lastActivity
      registrationFile { name description mcpEndpoint a2aEndpoint oasfEndpoint webEndpoint emailEndpoint }
    }
    reputation: agentFeedbackStats_collection(interval: day, where: {agent: $agent}, orderBy: timestamp, orderDirection: desc, first: 1) {
      feedbackCreated feedbackRevoked valueDeltaSum
    }
    validation: agentValidationStats_collection(interval: day, where: {agent: $agent}, orderBy: timestamp, orderDirection: desc, first: 1) {
      validationResponses scoreSum
    }
    feedbacks(where: {agent_: {id: $id}, isRevoked: false}, orderBy: createdAt, orderDirection: desc, first: $first, skip: $feedbackSkip) {
      id clientAddress value tag1 tag2 createdAt isRevoked feedbackFile { text }
    }
    validations(where: {agent_: {id: $id}}, orderBy: createdAt, orderDirection: desc, first: $first, skip: $validationSkip) {
      id validatorAddress response tag status createdAt
    }
  }
  """

  def new(registry, endpoint, opts \\ []) do
    with {:ok, ref} <- Ref.new(registry, 0),
         true <- is_binary(endpoint) and safe_endpoint?(endpoint),
         true <- Keyword.keyword?(opts) and Keyword.keys(opts) -- [:headers] == [],
         headers = Keyword.get(opts, :headers, []),
         true <-
           is_list(headers) and
             Enum.all?(headers, fn
               {key, value} when is_binary(key) and is_binary(value) -> true
               _ -> false
             end) do
      {:ok, %__MODULE__{registry: ref.registry, endpoint: endpoint, headers: headers}}
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def load(%__MODULE__{} = client, token_id, opts \\ []) do
    with {:ok, ref} <- Ref.new(client.registry, token_id),
         {:ok, options} <- Snapshot.options(opts),
         {:ok, data} <-
           request(client, %{
             id: Ref.key(ref),
             agent: Ref.key(ref),
             chain: Integer.to_string(ref.chain_id),
             first: options.limit + 1,
             feedbackSkip: options.feedback_offset,
             validationSkip: options.validation_offset
           }) do
      Snapshot.from_graphql(ref, data, opts)
    end
  end

  defp request(client, variables) do
    case Req.post(client.endpoint,
           headers: client.headers,
           json: %{query: @query, variables: variables},
           retry: false,
           redirect: false,
           http_errors: :return,
           raw: true,
           compressed: false,
           into: &receive_chunk/2,
           receive_timeout: 10_000,
           connect_options: [timeout: 5_000]
         ) do
      {:ok, %{private: %{erc8004_too_large: true}}} ->
        {:error, :response_too_large}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        decode_envelope(body)

      {:ok, %{status: 200}} ->
        {:error, :invalid_data}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, _} ->
        {:error, :unavailable}
    end
  end

  defp receive_chunk({:data, chunk}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(chunk) > 2_000_000 do
      {:halt,
       {request,
        %{response | body: "", private: Map.put(response.private, :erc8004_too_large, true)}}}
    else
      {:cont, {request, %{response | body: body <> chunk}}}
    end
  end

  defp decode_envelope(raw) do
    case Jason.decode(raw) do
      {:ok, body} when is_map(body) ->
        cond do
          Map.get(body, "errors", []) != [] -> {:error, :indexer_error}
          is_map(body["data"]) -> {:ok, body["data"]}
          true -> {:error, :invalid_data}
        end

      _ ->
        {:error, :invalid_data}
    end
  end

  defp safe_endpoint?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host, userinfo: nil, fragment: nil}
      when is_binary(host) and host != "" ->
        not String.match?(url, ~r/[\s\x00-\x1f\x7f]/)

      _ ->
        false
    end
  end
end
