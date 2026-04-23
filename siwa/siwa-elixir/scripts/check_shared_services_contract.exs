defmodule SharedServicesContractCheck do
  @contract_path Path.expand(
                   "../../../../regents-cli/docs/regent-services-contract.openapiv3.yaml",
                   __DIR__
                 )

  @required_operations [
    {"/v1/agent/siwa/nonce", "createSharedAgentSiwaNonce"},
    {"/v1/agent/siwa/verify", "verifySharedAgentSiwaSession"},
    {"/v1/agent/siwa/http-verify", "verifySharedSiwaHttpEnvelope"},
    {"/internal/keyring/health", "siwaKeyringHealth"},
    {"/internal/keyring/create-wallet", "siwaKeyringCreateWallet"},
    {"/internal/keyring/has-wallet", "siwaKeyringHasWallet"},
    {"/internal/keyring/get-address", "siwaKeyringGetAddress"},
    {"/internal/keyring/sign-message", "siwaKeyringSignMessage"},
    {"/internal/keyring/sign-raw-message", "siwaKeyringSignRawMessage"},
    {"/internal/keyring/sign-transaction", "siwaKeyringSignTransaction"},
    {"/internal/keyring/sign-authorization", "siwaKeyringSignAuthorization"}
  ]

  @required_schemas [
    "SiwaNonceRequest",
    "SiwaNonceResponse",
    "SiwaVerifyRequest",
    "SiwaVerifyResponse",
    "SiwaHttpVerifyRequest",
    "SiwaHttpVerifyResponse",
    "ErrorEnvelope",
    "LooseObject"
  ]

  def run do
    contract = File.read!(@contract_path)

    missing_operations =
      @required_operations
      |> Enum.reject(fn {path, operation_id} ->
        operation_present?(contract, path, operation_id)
      end)
      |> Enum.map(fn {path, operation_id} -> "#{path} -> #{operation_id}" end)

    missing_schemas =
      @required_schemas
      |> Enum.reject(fn schema -> String.contains?(contract, "    #{schema}:\n") end)

    case {missing_operations, missing_schemas} do
      {[], []} ->
        Mix.shell().info("Shared services contract covers SIWA routes and response envelopes.")

      _ ->
        raise Mix.Error,
          message:
            Enum.join(
              [
                missing_message("Missing operations", missing_operations),
                missing_message("Missing schemas", missing_schemas)
              ]
              |> Enum.reject(&is_nil/1),
              "\n"
            )
    end
  end

  defp operation_present?(contract, path, operation_id) do
    case path_section(contract, path) do
      {:ok, section} -> String.contains?(section, "operationId: #{operation_id}")
      :error -> false
    end
  end

  defp path_section(contract, path) do
    case String.split(contract, "  #{path}:\n", parts: 2) do
      [_before, section] ->
        {:ok, section |> String.split(~r/\n  \//, parts: 2) |> hd()}

      [_] ->
        :error
    end
  end

  defp missing_message(_label, []), do: nil

  defp missing_message(label, items) do
    "#{label}: #{Enum.join(items, ", ")}"
  end
end

SharedServicesContractCheck.run()
