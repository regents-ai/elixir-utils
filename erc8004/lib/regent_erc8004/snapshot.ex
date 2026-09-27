defmodule RegentERC8004.Snapshot do
  @moduledoc """
  Explicit display DTO for indexed evidence. Does not accept arbitrary Ash records.
  An Ash action may project authorized data into this same GraphQL-shaped boundary.
  Missing aggregates are unavailable, not a zero score. Activity covers loaded pages only.
  """
  alias RegentERC8004.Ref
  @enforce_keys [:agent, :reputation, :validation, :feedback, :validations, :activity]
  defstruct [:agent, :reputation, :validation, :feedback, :validations, :activity]

  @doc "Decode the selected indexer fields; unknown fields are discarded. No dynamic atoms."
  def from_graphql(%Ref{} = ref, data, opts \\ []) do
    with {:ok, options} <- options(opts) do
      decode(ref, data, options)
    end
  end

  @doc false
  def options(opts) do
    if Keyword.keyword?(opts) and
         Keyword.keys(opts) -- [:limit, :feedback_offset, :validation_offset] == [] do
      values = Map.new([limit: 10, feedback_offset: 0, validation_offset: 0] ++ opts)

      if values.limit in 1..50 and values.feedback_offset in 0..5000 and
           values.validation_offset in 0..5000,
         do: {:ok, values},
         else: {:error, :invalid_options}
    else
      {:error, :invalid_options}
    end
  end

  defp decode(ref, data, options) do
    protocol = field!(data, "protocol")

    reported_registry =
      "eip155:#{integer!(field!(protocol, "chainId"))}:#{text!(field!(protocol, "identityRegistry"))}"

    if Ref.new(reported_registry, ref.agent_id) != {:ok, ref} do
      {:error, :identity_mismatch}
    else
      decode_agent(ref, data, options)
    end
  rescue
    ArgumentError -> {:error, :invalid_data}
  end

  defp decode_agent(ref, data, options) do
    case field!(data, "agent") do
      nil ->
        {:error, :not_found}

      raw ->
        if integer!(field!(raw, "chainId")) != ref.chain_id or
             integer!(field!(raw, "agentId")) != ref.agent_id do
          {:error, :identity_mismatch}
        else
          feedback =
            page!(field!(data, "feedbacks"), &feedback!/1, options.limit, options.feedback_offset)

          validations =
            page!(
              field!(data, "validations"),
              &validation!/1,
              options.limit,
              options.validation_offset
            )

          events =
            Enum.map(
              feedback.entries,
              &%{kind: "Feedback", at: &1.at, actor: &1.reviewer, value: &1.value}
            ) ++
              Enum.map(
                validations.entries,
                &%{
                  kind: "Validation · #{&1.status}",
                  at: &1.at,
                  actor: &1.validator,
                  value: &1.score
                }
              )

          {:ok,
           %__MODULE__{
             agent: agent!(ref, raw),
             reputation: summary!(field!(data, "reputation"), :feedback),
             validation: summary!(field!(data, "validation"), :validation),
             feedback: feedback,
             validations: validations,
             activity: Enum.sort_by(events, &DateTime.to_unix(&1.at), :desc)
           }}
        end
    end
  rescue
    ArgumentError -> {:error, :invalid_data}
  end

  defp agent!(ref, raw) do
    registration = field!(raw, "registrationFile")
    file = if is_nil(registration), do: %{}, else: map!(registration)

    services =
      for {key, label} <- [
            {"mcpEndpoint", "MCP"},
            {"a2aEndpoint", "A2A"},
            {"oasfEndpoint", "OASF"},
            {"webEndpoint", "Web"},
            {"emailEndpoint", "Email"}
          ],
          url = nullable_text!(Map.get(file, key)),
          url not in [nil, ""],
          do: %{protocol: label, url: url}

    %{
      ref: ref,
      name: nullable_text!(Map.get(file, "name")),
      description: nullable_text!(Map.get(file, "description")),
      owner: text!(field!(raw, "owner")),
      last_activity: nullable_time!(field!(raw, "lastActivity")),
      services: services
    }
  end

  defp summary!([], _), do: %{status: :unavailable, count: nil, average: nil}

  defp summary!([raw], kind) do
    {count, sum} =
      case kind do
        :feedback ->
          created = integer!(field!(raw, "feedbackCreated"))
          revoked = integer!(field!(raw, "feedbackRevoked"))
          if revoked > created, do: invalid!()
          {created - revoked, decimal!(field!(raw, "valueDeltaSum"))}

        :validation ->
          {integer!(field!(raw, "validationResponses")), decimal!(field!(raw, "scoreSum"))}
      end

    if count == 0 and not Decimal.equal?(sum, 0), do: invalid!()

    if kind == :validation and
         (Decimal.negative?(sum) or Decimal.compare(sum, Decimal.new(count * 100)) == :gt),
       do: invalid!()

    average =
      if count > 0 do
        precision =
          max(
            28,
            byte_size(Integer.to_string(sum.coef)) + abs(sum.exp) +
              byte_size(Integer.to_string(count)) + 8
          )

        Decimal.Context.with(%Decimal.Context{precision: precision}, fn ->
          sum |> Decimal.div(count) |> Decimal.round(2, :half_up)
        end)
      end

    %{status: if(count == 0, do: :empty, else: :ready), count: count, average: average}
  end

  defp summary!(_, _), do: invalid!()

  defp page!(rows, decoder, limit, offset) when is_list(rows) do
    if length(rows) > limit + 1, do: invalid!()
    decoded = Enum.map(rows, decoder)
    has_more = length(decoded) > limit

    %{
      entries: Enum.take(decoded, limit),
      has_more: has_more,
      offset: offset,
      next_offset: if(has_more and offset + limit <= 5000, do: offset + limit),
      limit_reached: has_more and offset + limit > 5000
    }
  end

  defp page!(_, _, _, _), do: invalid!()

  defp feedback!(raw) do
    if field!(raw, "isRevoked") != false, do: invalid!()
    file = field!(raw, "feedbackFile")
    text = if is_nil(file), do: nil, else: nullable_text!(field!(file, "text"))

    %{
      id: text!(field!(raw, "id")),
      reviewer: text!(field!(raw, "clientAddress")),
      value: decimal!(field!(raw, "value")),
      at: time!(field!(raw, "createdAt")),
      text: text,
      tags:
        [nullable_text!(field!(raw, "tag1")), nullable_text!(field!(raw, "tag2"))]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.uniq()
    }
  end

  defp validation!(raw) do
    status = field!(raw, "status")
    if status not in ["PENDING", "COMPLETED", "EXPIRED"], do: invalid!()
    score = field!(raw, "response")
    if not is_nil(score) and (not is_integer(score) or score not in 0..100), do: invalid!()
    if status == "COMPLETED" and is_nil(score), do: invalid!()

    %{
      id: text!(field!(raw, "id")),
      validator: text!(field!(raw, "validatorAddress")),
      status: status,
      score: if(status == "COMPLETED", do: score),
      tag: nullable_text!(field!(raw, "tag")),
      at: time!(field!(raw, "createdAt"))
    }
  end

  defp map!(value) when is_map(value), do: value
  defp map!(_), do: invalid!()

  defp field!(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> invalid!()
    end
  end

  defp field!(_, _), do: invalid!()
  defp text!(value) when is_binary(value) and byte_size(value) <= 65_536, do: value
  defp text!(_), do: invalid!()
  defp nullable_text!(nil), do: nil
  defp nullable_text!(value), do: text!(value)
  defp integer!(value) when is_integer(value) and value >= 0, do: value

  defp integer!(value) when is_binary(value) and byte_size(value) <= 78 do
    if Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, value),
      do: String.to_integer(value),
      else: invalid!()
  end

  defp integer!(_), do: invalid!()

  defp decimal!(value) when is_binary(value) and byte_size(value) <= 256 do
    if Regex.match?(~r/\A-?[0-9]+(?:\.[0-9]+)?\z/, value),
      do: Decimal.new(value),
      else: invalid!()
  end

  defp decimal!(value) when is_integer(value), do: Decimal.new(value)
  defp decimal!(_), do: invalid!()
  defp nullable_time!(nil), do: nil
  defp nullable_time!(value), do: time!(value)

  defp time!(value) do
    case DateTime.from_unix(integer!(value)) do
      {:ok, datetime} -> datetime
      _ -> invalid!()
    end
  end

  defp invalid!, do: raise(ArgumentError, "invalid indexed evidence")
end
