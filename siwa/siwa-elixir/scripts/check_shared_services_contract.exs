defmodule SharedServicesContractCheck do
  @contract_path Path.expand(
                   "../../../../regents-cli/docs/regent-services-contract.openapiv3.yaml",
                   __DIR__
                 )
  @keyring_router_path Path.expand(
                         "../apps/siwa_keyring/lib/siwa_keyring/router.ex",
                         __DIR__
                       )
  @local_surface_paths [
    Path.expand("../README.md", __DIR__),
    Path.expand("../apps/siwa/README.md", __DIR__),
    Path.expand("../apps/siwa/lib", __DIR__),
    Path.expand("../apps/siwa/test", __DIR__),
    Path.expand("../apps/siwa_keyring/README.md", __DIR__),
    Path.expand("../apps/siwa_keyring/lib", __DIR__),
    Path.expand("../apps/siwa_keyring/test", __DIR__),
    Path.expand("../fixtures/siwa", __DIR__)
  ]
  @canonical_chain_id 8453
  @forbidden_chain_id 84_532
  @forbidden_chain_terms [
    Integer.to_string(@forbidden_chain_id),
    "eip155:" <> Integer.to_string(@forbidden_chain_id),
    "Base " <> "Se" <> "polia",
    "base " <> "se" <> "polia",
    "https://" <> "se" <> "polia" <> ".base.org"
  ]

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
    "KeyringWalletActionEnvelope",
    "KeyringSignTransactionRequest",
    "KeyringSignAuthorizationRequest",
    "KeyringSignatureResponse",
    "KeyringSignedTransactionResponse",
    "KeyringSignedAuthorizationResponse"
  ]

  @required_security_schemes [
    "KeyringHmacTimestamp",
    "KeyringHmacRequestId",
    "KeyringHmacSignature"
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

    missing_security_schemes =
      @required_security_schemes
      |> Enum.reject(fn scheme -> String.contains?(contract, "    #{scheme}:\n") end)

    missing_keyring_request_id_paths =
      @keyring_operations
      |> Enum.reject(fn
        {{"get", "/internal/keyring/health"}, _operation_id} ->
          true

        {{_method, path}, _operation_id} ->
          case path_section(contract, path) do
            {:ok, section} -> String.contains?(section, "KeyringHmacRequestId")
            :error -> false
          end
      end)
      |> Enum.map(fn {{method, path}, operation_id} ->
        "#{String.upcase(method)} #{path} -> #{operation_id}"
      end)

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

    base_chain_schema_errors = base_chain_schema_errors(contract)
    base_chain_config_errors = base_chain_config_errors()
    local_chain_drift = local_chain_drift()

    case {
      missing_operations,
      missing_schemas,
      missing_security_schemes,
      missing_keyring_request_id_paths,
      missing_router_routes,
      extra_router_routes,
      missing_contract_keyring_paths,
      extra_contract_keyring_paths,
      base_chain_schema_errors,
      base_chain_config_errors,
      local_chain_drift
    } do
      {[], [], [], [], [], [], [], [], [], [], []} ->
        Mix.shell().info("Shared services contract covers SIWA routes and response envelopes.")

      _ ->
        raise Mix.Error,
          message:
            Enum.join(
              [
                missing_message("Missing operations", missing_operations),
                missing_message("Missing schemas", missing_schemas),
                missing_message("Missing security schemes", missing_security_schemes),
                missing_message(
                  "Missing keyring request-id security",
                  missing_keyring_request_id_paths
                ),
                missing_message("Missing keyring router routes", missing_router_routes),
                missing_message("Extra keyring router routes", extra_router_routes),
                missing_message("Missing keyring contract paths", missing_contract_keyring_paths),
                missing_message("Extra keyring contract paths", extra_contract_keyring_paths),
                missing_message("Base chain contract drift", base_chain_schema_errors),
                missing_message("Base chain runtime drift", base_chain_config_errors),
                missing_message("Base chain local fixture/test drift", local_chain_drift)
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

  defp schema_section(contract, schema) do
    case String.split(contract, "    #{schema}:\n", parts: 2) do
      [_before, section] ->
        {:ok, section |> String.split(~r/\n    [A-Za-z0-9]+:/, parts: 2) |> hd()}

      [_] ->
        :error
    end
  end

  defp base_chain_schema_errors(contract) do
    case schema_section(contract, "BaseChainId") do
      {:ok, section} ->
        cond do
          not Regex.match?(~r/type:\s+integer/, section) ->
            ["BaseChainId must remain an integer schema"]

          not Regex.match?(~r/enum:\s+\[#{@canonical_chain_id}\]/, section) ->
            ["BaseChainId must remain enum [#{@canonical_chain_id}]"]

          true ->
            []
        end

      :error ->
        ["BaseChainId schema is missing"]
    end
  end

  defp base_chain_config_errors do
    [
      chain_config_error("Siwa.Registry.registry_addresses", Siwa.Registry.registry_addresses()),
      chain_config_error(
        "Siwa.Registry.reputation_addresses",
        Siwa.Registry.reputation_addresses()
      ),
      chain_config_error("Siwa.Registry.rpc_endpoints", Siwa.Registry.rpc_endpoints())
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp chain_config_error(label, values) do
    chain_ids = values |> Map.keys() |> Enum.sort()

    if chain_ids == [@canonical_chain_id] do
      nil
    else
      "#{label} must only expose #{@canonical_chain_id}; found #{inspect(chain_ids)}"
    end
  end

  defp local_chain_drift do
    @local_surface_paths
    |> Enum.flat_map(&surface_files/1)
    |> Enum.flat_map(fn path ->
      source = File.read!(path)

      @forbidden_chain_terms
      |> Enum.filter(&String.contains?(source, &1))
      |> Enum.map(fn _term -> Path.relative_to(path, Path.expand("..", __DIR__)) end)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp surface_files(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.flat_map(fn entry -> surface_files(Path.join(path, entry)) end)

      true ->
        []
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
