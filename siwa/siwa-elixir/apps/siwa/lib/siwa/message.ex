defmodule Siwa.Message do
  @moduledoc "Builds and parses the SIWA sign-in message."

  @required [:domain, :address, :uri, :agent_id, :agent_registry, :chain_id, :nonce, :issued_at]
  @positive_int_regex ~r/^[1-9][0-9]*$/
  @line_labels [
    {"URI", :uri},
    {"Version", :version},
    {"Agent ID", :agent_id},
    {"Agent Registry", :agent_registry},
    {"Chain ID", :chain_id},
    {"Nonce", :nonce},
    {"Issued At", :issued_at},
    {"Expiration Time", :expiration_time},
    {"Not Before", :not_before},
    {"Request ID", :request_id}
  ]
  @normalized_string_keys %{
    "domain" => :domain,
    "address" => :address,
    "statement" => :statement,
    "uri" => :uri,
    "version" => :version,
    "agent_id" => :agent_id,
    "agent_registry" => :agent_registry,
    "chain_id" => :chain_id,
    "nonce" => :nonce,
    "issued_at" => :issued_at,
    "expiration_time" => :expiration_time,
    "not_before" => :not_before,
    "request_id" => :request_id
  }

  def build(fields) do
    normalized = normalize_fields(fields)
    Enum.each(@required, &ensure_present!(normalized, &1))

    statement_lines =
      case normalized[:statement] do
        nil -> [""]
        statement -> [statement, ""]
      end

    ([
       "#{normalized[:domain]} wants you to sign in with your Agent account:",
       normalized[:address],
       ""
     ] ++
       statement_lines ++
       [
         "URI: #{normalized[:uri]}",
         "Version: #{normalized[:version] || "1"}",
         "Agent ID: #{normalized[:agent_id]}",
         "Agent Registry: #{normalized[:agent_registry]}",
         "Chain ID: #{normalized[:chain_id]}",
         "Nonce: #{normalized[:nonce]}",
         "Issued At: #{normalized[:issued_at]}"
       ] ++
       optional_lines(normalized))
    |> Enum.join("\n")
  end

  def parse(message) when is_binary(message) do
    lines = String.split(message, "\n", trim: false)

    with [header, address, "" | rest] <- lines,
         {:ok, domain} <- parse_domain(header),
         {statement, attributes} <- split_statement(rest),
         {:ok, parsed} <- parse_attributes(attributes) do
      {:ok,
       parsed
       |> Map.put(:domain, domain)
       |> Map.put(:address, address)
       |> maybe_put_statement(statement)}
    else
      _ -> {:error, :invalid_message}
    end
  end

  def validate_canonical(message, expected) when is_binary(message) and is_map(expected) do
    expected = normalize_fields(expected)

    with {:ok, parsed} <- parse(String.trim(message)),
         true <- parsed.domain == expected[:domain],
         true <-
           parsed.address |> normalize_address() == expected[:address] |> normalize_address(),
         true <- parsed.uri == expected[:uri],
         true <- Map.get(parsed, :version, "1") == "1",
         true <- parsed.agent_id == expected[:agent_id],
         true <- parsed.chain_id == expected[:chain_id],
         {:ok, parsed_registry} <- parse_agent_registry(parsed.agent_registry),
         {:ok, expected_registry} <- parse_agent_registry(expected[:agent_registry]),
         true <- parsed_registry == expected_registry,
         true <- parsed_registry.chain_id == parsed.chain_id,
         true <- Map.get(parsed, :statement) == expected[:statement],
         true <- parsed.nonce == expected[:nonce],
         :ok <- validate_issued_at(parsed.issued_at) do
      :ok
    else
      _ -> {:error, :invalid_canonical_message}
    end
  end

  def validate_canonical(_message, _expected), do: {:error, :invalid_canonical_message}

  def normalize_fields(fields) when is_map(fields), do: Enum.into(fields, %{}, &normalize_pair/1)

  def normalize_fields(fields) when is_list(fields),
    do: fields |> Enum.into(%{}) |> normalize_fields()

  defp normalize_pair({key, value}) when is_binary(key), do: {normalize_key(key), value}
  defp normalize_pair({key, value}), do: {key, value}

  defp normalize_key(other), do: Map.get(@normalized_string_keys, other, other)

  defp ensure_present!(fields, key) do
    case Map.get(fields, key) do
      nil -> raise ArgumentError, "missing SIWA field #{key}"
      _ -> :ok
    end
  end

  defp optional_lines(fields) do
    Enum.flat_map([:expiration_time, :not_before, :request_id], fn key ->
      case fields[key] do
        nil -> []
        value -> ["#{format_label(key)}: #{value}"]
      end
    end)
  end

  defp format_label(:expiration_time), do: "Expiration Time"
  defp format_label(:not_before), do: "Not Before"
  defp format_label(:request_id), do: "Request ID"

  defp parse_domain(header) do
    suffix = " wants you to sign in with your Agent account:"

    if String.ends_with?(header, suffix) do
      {:ok, String.replace_suffix(header, suffix, "")}
    else
      {:error, :invalid_header}
    end
  end

  defp split_statement(["" | rest]), do: {nil, rest}
  defp split_statement([statement, "" | rest]), do: {statement, rest}
  defp split_statement(other), do: {nil, other}

  defp parse_attributes(lines) do
    Enum.reduce_while(lines, {:ok, %{}}, fn line, {:ok, acc} ->
      case String.split(line, ": ", parts: 2) do
        [label, value] ->
          case Enum.find(@line_labels, fn {known, _} -> known == label end) do
            nil ->
              {:halt, {:error, :invalid_attribute}}

            {_, key} ->
              if Map.has_key?(acc, key) do
                {:halt, {:error, :invalid_attribute}}
              else
                case cast_value(key, value) do
                  {:ok, casted} -> {:cont, {:ok, Map.put(acc, key, casted)}}
                  {:error, _reason} -> {:halt, {:error, :invalid_attribute}}
                end
              end
          end

        _ ->
          {:halt, {:error, :invalid_attribute}}
      end
    end)
  end

  defp cast_value(:agent_id, value), do: parse_positive_integer(value)
  defp cast_value(:chain_id, value), do: parse_positive_integer(value)
  defp cast_value(_key, value), do: {:ok, value}

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  defp maybe_put_statement(map, nil), do: map
  defp maybe_put_statement(map, statement), do: Map.put(map, :statement, statement)

  defp parse_agent_registry("eip155:" <> rest) do
    with [chain_id, registry_address] <- String.split(rest, ":", parts: 2),
         true <- Regex.match?(@positive_int_regex, chain_id),
         {:ok, normalized_address} <- normalize_required_address(registry_address) do
      {:ok, %{chain_id: String.to_integer(chain_id), address: normalized_address}}
    else
      _ -> {:error, :invalid_agent_registry}
    end
  end

  defp parse_agent_registry(_value), do: {:error, :invalid_agent_registry}

  defp validate_issued_at(issued_at) do
    case DateTime.from_iso8601(issued_at) do
      {:ok, _datetime, 0} -> :ok
      _ -> {:error, :invalid_issued_at}
    end
  end

  defp normalize_address(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp normalize_address(value), do: value

  defp normalize_required_address(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "",
      do: {:error, :invalid_address},
      else: {:ok, String.downcase(trimmed)}
  end

  defp normalize_required_address(_value), do: {:error, :invalid_address}
end
