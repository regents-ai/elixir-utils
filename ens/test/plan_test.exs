defmodule AgentEns.PlanTest do
  use ExUnit.Case, async: true

  alias AgentEns.Link
  alias AgentEns.Plan

  defmodule RpcReady do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @registry "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @signer "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      case {String.downcase(to), data} do
        {@ens_registry, "0x0178b8bf" <> _node} ->
          {:ok, address_word(@resolver)}

        {@ens_registry, "0x02571be3" <> _node} ->
          {:ok, address_word(@signer)}

        {@resolver, "0x59d1d43c" <> _rest} ->
          {:ok, encode_string("")}

        {@resolver, "0x01ffc9a7" <> "59d1d43c" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x01ffc9a7" <> "3b3b57de" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x3b3b57de" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@resolver, "0x691f3431" <> _rest} ->
          {:ok, encode_string("")}

        {@registry, "0x6352211e" <> _rest} ->
          {:ok, address_word(@signer)}

        {@registry, "0x081812fc" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@registry, "0xc87b56dd" <> _rest} ->
          uri =
            "data:application/json," <>
              URI.encode_www_form(
                Jason.encode!(%{
                  "type" => "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
                  "name" => "Demo Agent",
                  "services" => [%{"name" => "ENS", "endpoint" => "old.eth", "version" => "v1"}]
                })
              )

          {:ok, encode_string(uri)}

        {@registry, "0xe985e9c5" <> _rest} ->
          {:ok, bool_word(false)}
      end
    end

    defp bool_word(true), do: "0x" <> String.pad_leading("1", 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defmodule RpcSatisfied do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @registry "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @signer "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      case {String.downcase(to), data} do
        {@ens_registry, "0x0178b8bf" <> _node} ->
          {:ok, address_word(@resolver)}

        {@ens_registry, "0x02571be3" <> _node} ->
          {:ok, address_word(@signer)}

        {@resolver, "0x59d1d43c" <> _rest} ->
          {:ok, encode_string("verified")}

        {@resolver, "0x01ffc9a7" <> "59d1d43c" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x01ffc9a7" <> "3b3b57de" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x3b3b57de" <> _rest} ->
          {:ok, address_word(@signer)}

        {@resolver, "0x691f3431" <> _rest} ->
          {:ok, encode_string("vitalik.eth")}

        {@registry, "0x6352211e" <> _rest} ->
          {:ok, address_word(@signer)}

        {@registry, "0x081812fc" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@registry, "0xc87b56dd" <> _rest} ->
          uri =
            "data:application/json," <>
              URI.encode_www_form(
                Jason.encode!(%{
                  "type" => "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
                  "name" => "Demo Agent",
                  "services" => [
                    %{"name" => "ENS", "endpoint" => "vitalik.eth", "version" => "v1"}
                  ]
                })
              )

          {:ok, encode_string(uri)}

        {@registry, "0xe985e9c5" <> _rest} ->
          {:ok, bool_word(false)}
      end
    end

    defp bool_word(true), do: "0x" <> String.pad_leading("1", 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defmodule RpcOffchain do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @registry "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @signer "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      case {String.downcase(to), data} do
        {@ens_registry, "0x0178b8bf" <> _node} ->
          {:ok, address_word(@resolver)}

        {@ens_registry, "0x02571be3" <> _node} ->
          {:ok, address_word(@signer)}

        {@resolver, "0x01ffc9a7" <> "59d1d43c" <> _padding} ->
          {:ok, bool_word(false)}

        {@resolver, "0x01ffc9a7" <> "9061b923" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x01ffc9a7" <> "3b3b57de" <> _padding} ->
          {:ok, bool_word(false)}

        {@resolver, "0x59d1d43c" <> _rest} ->
          {:error, {:rpc_error, :offchain_only}}

        {@resolver, "0x691f3431" <> _rest} ->
          {:ok, encode_string("")}

        {@registry, "0x6352211e" <> _rest} ->
          {:ok, address_word(@signer)}

        {@registry, "0x081812fc" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@registry, "0xc87b56dd" <> _rest} ->
          {:ok, encode_string("")}

        {@registry, "0xe985e9c5" <> _rest} ->
          {:ok, bool_word(false)}
      end
    end

    defp bool_word(true), do: "0x" <> String.pad_leading("1", 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defmodule RpcEmptyTokenUri do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @registry "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @signer "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      case {String.downcase(to), data} do
        {@ens_registry, "0x0178b8bf" <> _node} ->
          {:ok, address_word(@resolver)}

        {@ens_registry, "0x02571be3" <> _node} ->
          {:ok, address_word(@signer)}

        {@resolver, "0x59d1d43c" <> _rest} ->
          {:ok, encode_string("")}

        {@resolver, "0x01ffc9a7" <> "59d1d43c" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x01ffc9a7" <> "3b3b57de" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x3b3b57de" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@resolver, "0x691f3431" <> _rest} ->
          {:ok, encode_string("")}

        {@registry, "0x6352211e" <> _rest} ->
          {:ok, address_word(@signer)}

        {@registry, "0x081812fc" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@registry, "0xc87b56dd" <> _rest} ->
          {:ok, encode_string("")}

        {@registry, "0xe985e9c5" <> _rest} ->
          {:ok, bool_word(false)}
      end
    end

    defp bool_word(true), do: "0x" <> String.pad_leading("1", 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defmodule BrokenFetcher do
    @behaviour AgentEns.ERC8004.Fetcher

    @impl true
    def fetch(_uri, _opts), do: {:error, :unreadable_registration}
  end

  defmodule RpcEquivalentEnsService do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @registry "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @signer "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      case {String.downcase(to), data} do
        {@ens_registry, "0x0178b8bf" <> _node} ->
          {:ok, address_word(@resolver)}

        {@ens_registry, "0x02571be3" <> _node} ->
          {:ok, address_word(@signer)}

        {@resolver, "0x59d1d43c" <> _rest} ->
          {:ok, encode_string("verified")}

        {@resolver, "0x01ffc9a7" <> "59d1d43c" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x01ffc9a7" <> "3b3b57de" <> _padding} ->
          {:ok, bool_word(true)}

        {@resolver, "0x3b3b57de" <> _rest} ->
          {:ok, address_word(@signer)}

        {@resolver, "0x691f3431" <> _rest} ->
          {:ok, encode_string("vitalik.eth")}

        {@registry, "0x6352211e" <> _rest} ->
          {:ok, address_word(@signer)}

        {@registry, "0x081812fc" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@registry, "0xc87b56dd" <> _rest} ->
          uri =
            "data:application/json," <>
              URI.encode_www_form(
                Jason.encode!(%{
                  "type" => "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
                  "name" => "Demo Agent",
                  "services" => [
                    %{"name" => "ENS", "endpoint" => "Vitalik.ETH.", "version" => "v1"}
                  ]
                })
              )

          {:ok, encode_string(uri)}

        {@registry, "0xe985e9c5" <> _rest} ->
          {:ok, bool_word(false)}
      end
    end

    defp bool_word(true), do: "0x" <> String.pad_leading("1", 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defmodule RpcSubnameNoResolver do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @registry "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
    @signer "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      case {String.downcase(to), data} do
        {@ens_registry, "0x0178b8bf" <> _node} ->
          {:ok, "0x" <> String.duplicate("0", 64)}

        {@ens_registry, "0x02571be3" <> _node} ->
          {:ok, address_word(@signer)}

        {@registry, "0x6352211e" <> _rest} ->
          {:ok, address_word(@signer)}

        {@registry, "0x081812fc" <> _rest} ->
          {:ok, address_word("0x0000000000000000000000000000000000000000")}

        {@registry, "0xc87b56dd" <> _rest} ->
          {:ok, encode_string("")}

        {@registry, "0xe985e9c5" <> _rest} ->
          {:ok, bool_word(false)}
      end
    end

    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defp canonical_link_input(overrides) do
    Map.merge(
      %{
        ens_name: "vitalik.eth",
        ens_chain_id: 1,
        ens_rpc_url: "https://ens.example.invalid",
        registry_chain_id: 8453,
        registry_rpc_url: "https://base.example.invalid",
        registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
        agent_id: 42
      },
      overrides
    )
  end

  test "plans both actions when ENS record and registration are out of sync" do
    assert {:ok, plan} =
             Plan.plan_link(
               canonical_link_input(%{
                 rpc_module: RpcReady,
                 signer_address: "0x1111111111111111111111111111111111111111",
                 include_reverse?: true
               })
             )

    assert plan.verify_status == :ens_record_missing
    assert plan.erc8004_status == :ens_service_mismatch
    assert plan.ens_write_status == :ready
    assert plan.erc8004_write_status == :ready
    assert Enum.any?(plan.actions, &(&1.kind == :set_ens_text and &1.status == :ready))

    assert Enum.any?(
             plan.actions,
             &(&1.kind == :update_erc8004_registration and &1.status == :ready)
           )
  end

  test "prepares both unsigned transactions from the shared planner" do
    assert {:ok, prepared} =
             Link.prepare_bidirectional_link(
               canonical_link_input(%{
                 rpc_module: RpcReady,
                 signer_address: "0x1111111111111111111111111111111111111111",
                 include_reverse?: true
               })
             )

    assert match?(%{tx: _}, prepared.ensip25)
    assert match?(%{tx: _, new_registration: _}, prepared.erc8004)
    assert match?(%{tx: _}, prepared.reverse)
  end

  test "marks already-satisfied records as no-op work" do
    assert {:ok, prepared} =
             Link.prepare_bidirectional_link(canonical_link_input(%{rpc_module: RpcSatisfied}))

    assert prepared.plan.verify_status == :verified
    assert prepared.plan.erc8004_status == :ens_service_present
    assert prepared.ensip25 == :noop
    assert prepared.erc8004 == :noop
    assert prepared.reverse == :skipped
  end

  test "blocks writes when no signer is available" do
    assert {:ok, prepared} =
             Link.prepare_bidirectional_link(
               canonical_link_input(%{
                 rpc_module: RpcReady,
                 include_reverse?: true
               })
             )

    assert prepared.plan.ens_write_status == :signer_required
    assert prepared.plan.erc8004_write_status == :signer_required
    assert prepared.plan.reverse_status == :signer_required
    assert prepared.ensip25 == :blocked
    assert prepared.erc8004 == :blocked
    assert prepared.reverse == :blocked
  end

  test "returns a blocked plan for offchain resolvers instead of failing" do
    assert {:ok, plan} =
             Plan.plan_link(
               canonical_link_input(%{
                 rpc_module: RpcOffchain,
                 signer_address: "0x1111111111111111111111111111111111111111"
               })
             )

    assert plan.verify_status == :ens_record_missing
    assert plan.ens_write_status == :unsupported_offchain_resolver

    assert Enum.any?(
             plan.actions,
             &(&1.kind == :set_ens_text and &1.status == :blocked and
                 &1.reason == :unsupported_offchain_resolver)
           )
  end

  test "blocks ERC-8004 updates when the current registration is unavailable" do
    assert {:ok, plan} =
             Plan.plan_link(
               canonical_link_input(%{
                 rpc_module: RpcEmptyTokenUri,
                 signer_address: "0x1111111111111111111111111111111111111111"
               })
             )

    assert plan.erc8004_status == :ens_service_missing
    assert plan.erc8004_write_status == :registration_unavailable

    assert Enum.any?(
             plan.actions,
             &(&1.kind == :update_erc8004_registration and &1.status == :blocked and
                 &1.reason == :registration_unavailable)
           )
  end

  test "keeps planning when the current registration cannot be read" do
    assert {:ok, plan} =
             Plan.plan_link(
               canonical_link_input(%{
                 rpc_module: RpcReady,
                 signer_address: "0x1111111111111111111111111111111111111111",
                 current_agent_uri: "https://example.invalid/agent.json",
                 erc8004_fetcher: BrokenFetcher
               })
             )

    assert plan.erc8004_registration == nil
    assert plan.erc8004_write_status == :registration_unavailable

    assert "The current ERC-8004 registration could not be loaded as a JSON registration file." in plan.warnings
  end

  test "treats normalization-equivalent ENS endpoints as already present" do
    assert {:ok, prepared} =
             Link.prepare_bidirectional_link(
               canonical_link_input(%{rpc_module: RpcEquivalentEnsService})
             )

    assert prepared.plan.erc8004_status == :ens_service_present
    assert prepared.erc8004 == :noop
  end

  test "accepts string agent ids for ENS planning and blocks token write checks cleanly" do
    assert {:ok, plan} =
             Plan.plan_link(
               canonical_link_input(%{
                 agent_id: "agent-42",
                 rpc_module: RpcReady,
                 signer_address: "0x1111111111111111111111111111111111111111",
                 current_agent_uri:
                   "data:application/json," <>
                     URI.encode_www_form(
                       Jason.encode!(%{
                         "type" => "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
                         "name" => "Demo Agent",
                         "services" => [
                           %{"name" => "ENS", "endpoint" => "vitalik.eth", "version" => "v1"}
                         ]
                       })
                     )
               })
             )

    assert plan.ensip25_key =~ "agent-42"
    assert plan.erc8004_status == :ens_service_present
    assert plan.erc8004_write_status == :registration_unavailable

    assert "String agent IDs are accepted for ENS planning, but ERC-8004 token ownership and approval checks require a numeric token ID." in plan.warnings
  end

  test "warns when a subname plan only checked the exact name resolver" do
    assert {:ok, plan} =
             Plan.plan_link(
               canonical_link_input(%{
                 ens_name: "app.demo.eth",
                 rpc_module: RpcSubnameNoResolver,
                 signer_address: "0x1111111111111111111111111111111111111111"
               })
             )

    assert "Only the exact name was checked. Wildcard or offchain subname resolution is not included in this plan." in plan.warnings
  end
end
