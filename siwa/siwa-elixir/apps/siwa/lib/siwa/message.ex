defmodule Siwa.Message do
  @moduledoc "Builds and parses the SIWA sign-in message."

  @required [:domain, :address, :uri, :agent_id, :agent_registry, :chain_id, :nonce, :issued_at]
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

  def normalize_fields(fields) when is_map(fields), do: Enum.into(fields, %{}, &normalize_pair/1)

  def normalize_fields(fields) when is_list(fields),
    do: fields |> Enum.into(%{}) |> normalize_fields()

  defp normalize_pair({key, value}) when is_binary(key), do: {normalize_key(key), value}
  defp normalize_pair({key, value}), do: {key, value}

  defp normalize_key("agentId"), do: :agent_id
  defp normalize_key("agentRegistry"), do: :agent_registry
  defp normalize_key("chainId"), do: :chain_id
  defp normalize_key("issuedAt"), do: :issued_at
  defp normalize_key("expirationTime"), do: :expiration_time
  defp normalize_key("notBefore"), do: :not_before
  defp normalize_key("requestId"), do: :request_id
  defp normalize_key(other), do: other

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
            nil -> {:halt, {:error, :invalid_attribute}}
            {_, key} -> {:cont, {:ok, Map.put(acc, key, cast_value(key, value))}}
          end

        _ ->
          {:halt, {:error, :invalid_attribute}}
      end
    end)
  end

  defp cast_value(:agent_id, value), do: String.to_integer(value)
  defp cast_value(:chain_id, value), do: String.to_integer(value)
  defp cast_value(_key, value), do: value

  defp maybe_put_statement(map, nil), do: map
  defp maybe_put_statement(map, statement), do: Map.put(map, :statement, statement)
end
