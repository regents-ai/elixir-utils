defmodule SharedServicesContractCheck do
  @contract_path Path.expand(
                   "../../../../regents-cli/docs/regent-services-contract.openapiv3.yaml",
                   __DIR__
                 )
  @keyring_router_path Path.expand(
                         "../apps/siwa_keyring/lib/siwa_keyring/router.ex",
                         __DIR__
                       )

  @siwa_operations %{
    {"post", "/v1/agent/siwa/nonce"} => "createSharedAgentSiwaNonce",
    {"post", "/v1/agent/siwa/verify"} => "verifySharedAgentSiwaSession",
    {"post", "/v1/agent/siwa/http-verify"} => "verifySharedSiwaHttpEnvelope"
  }

  @keyring_operations %{
    {"get", "/internal/keyring/health"} => "siwaKeyringHealth",
    {"post", "/internal/keyring/create-wallet"} => "siwaKeyringCreateWallet",
    {"post", "/internal/keyring/has-wallet"} => "siwaKeyringHasWallet",
    {"post", "/internal/keyring/get-address"} => "siwaKeyringGetAddress",
    {"post", "/internal/keyring/sign-message"} => "siwaKeyringSignMessage",
    {"post", "/internal/keyring/sign-raw-message"} => "siwaKeyringSignRawMessage",
    {"post", "/internal/keyring/sign-transaction"} => "siwaKeyringSignTransaction",
    {"post", "/internal/keyring/sign-authorization"} => "siwaKeyringSignAuthorization"
  }

  @required_schemas [
    "SiwaNonceRequest",
    "SiwaNonceResponse",
    "SiwaVerifyRequest",
    "SiwaVerifyResponse",
    "SiwaHttpVerifyRequest",
    "SiwaHttpVerifyResponse",
    "ErrorEnvelope",
    "LooseObject",
    "SimpleError",
    "KeyringHealthResponse",
    "KeyringWalletResponse",
    "KeyringHasWalletResponse",
    "KeyringAddressResponse",
    "KeyringSignMessageRequest",
    "KeyringSignRawMessageRequest",
    "KeyringSignTransactionRequest",
    "KeyringSignAuthorizationRequest",
    "KeyringSignatureResponse",
    "KeyringSignedTransactionResponse",
    "KeyringSignedAuthorizationResponse"
  ]

  def run do
    contract = File.read!(@contract_path)
    keyring_router = File.read!(@keyring_router_path)

    missing_operations =
      required_operations()
      |> Enum.reject(fn {{method, path}, operation_id} ->
        operation_present?(contract, method, path, operation_id)
      end)
      |> Enum.map(fn {{method, path}, operation_id} ->
        "#{String.upcase(method)} #{path} -> #{operation_id}"
      end)

    missing_schemas =
      @required_schemas
      |> Enum.reject(fn schema -> String.contains?(contract, "    #{schema}:\n") end)

    router_routes = keyring_router |> keyring_router_routes() |> MapSet.new()
    expected_keyring_routes = @keyring_operations |> Map.keys() |> MapSet.new()
    contract_keyring_paths = contract |> keyring_contract_paths() |> MapSet.new()

    expected_keyring_paths =
      expected_keyring_routes
      |> Enum.map(fn {_method, path} -> path end)
      |> MapSet.new()

    missing_router_routes =
      expected_keyring_routes
      |> MapSet.difference(router_routes)
      |> format_route_set()

    extra_router_routes =
      router_routes
      |> MapSet.difference(expected_keyring_routes)
      |> format_route_set()

    missing_contract_keyring_paths =
      expected_keyring_paths
      |> MapSet.difference(contract_keyring_paths)
      |> Enum.sort()

    extra_contract_keyring_paths =
      contract_keyring_paths
      |> MapSet.difference(expected_keyring_paths)
      |> Enum.sort()

    case {
      missing_operations,
      missing_schemas,
      missing_router_routes,
      extra_router_routes,
      missing_contract_keyring_paths,
      extra_contract_keyring_paths
    } do
      {[], [], [], [], [], []} ->
        Mix.shell().info("Shared services contract covers SIWA routes and response envelopes.")

      _ ->
        raise Mix.Error,
          message:
            Enum.join(
              [
                missing_message("Missing operations", missing_operations),
                missing_message("Missing schemas", missing_schemas),
                missing_message("Missing keyring router routes", missing_router_routes),
                missing_message("Extra keyring router routes", extra_router_routes),
                missing_message("Missing keyring contract paths", missing_contract_keyring_paths),
                missing_message("Extra keyring contract paths", extra_contract_keyring_paths)
              ]
              |> Enum.reject(&is_nil/1),
              "\n"
            )
    end
  end

  defp required_operations, do: Map.merge(@siwa_operations, @keyring_operations)

  defp operation_present?(contract, method, path, operation_id) do
    case path_section(contract, path) do
      {:ok, section} ->
        String.contains?(section, "    #{method}:\n") and
          String.contains?(section, "operationId: #{operation_id}")

      :error ->
        false
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

  defp keyring_router_routes(source) do
    prefix =
      case Regex.run(~r/@prefix\s+"([^"]+)"/, source) do
        [_, value] -> value
        _ -> raise Mix.Error, message: "Could not read keyring router prefix"
      end

    ~r/^\s*(get|post)\s+@prefix\s+<>\s+"([^"]+)"/m
    |> Regex.scan(source)
    |> Enum.map(fn [_match, method, suffix] -> {method, prefix <> suffix} end)
  end

  defp keyring_contract_paths(contract) do
    ~r/^\s{2}(\/internal\/keyring\/[^:]+):/m
    |> Regex.scan(contract)
    |> Enum.map(fn [_match, path] -> path end)
  end

  defp format_route_set(routes) do
    routes
    |> Enum.map(fn {method, path} -> "#{String.upcase(method)} #{path}" end)
    |> Enum.sort()
  end

  defp missing_message(_label, []), do: nil

  defp missing_message(label, items) do
    "#{label}: #{Enum.join(items, ", ")}"
  end
end

SharedServicesContractCheck.run()
