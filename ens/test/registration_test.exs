defmodule AgentEns.RegistrationTest do
  use ExUnit.Case, async: true

  alias AgentEns.Error
  alias AgentEns.ERC8004.Registration

  defmodule StaticFetcher do
    @behaviour AgentEns.ERC8004.Fetcher

    @impl true
    def fetch(_uri, _opts) do
      {:ok,
       Jason.encode!(%{
         "type" => "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
         "name" => "Demo Agent",
         "services" => [
           %{"name" => "MCP", "endpoint" => "https://demo.example/mcp", "version" => "2025-06-18"}
         ]
       })}
    end
  end

  defmodule EchoPublisher do
    @behaviour AgentEns.ERC8004.Publisher

    @impl true
    def publish(binary, _opts) when is_binary(binary) do
      {:ok, "data:application/json," <> URI.encode_www_form(binary)}
    end
  end

  test "upserts a canonical ENS service entry and preserves unknown fields" do
    registration = %{
      "type" => "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
      "name" => "Demo Agent",
      "services" => [
        %{"name" => "ENS", "endpoint" => "old.eth", "version" => "v1"},
        %{"name" => "MCP", "endpoint" => "https://demo.example/mcp", "version" => "2025-06-18"}
      ],
      "extra" => %{"keep" => true}
    }

    updated = Registration.upsert_ens_service(registration, "new.eth")

    assert updated["extra"] == %{"keep" => true}

    assert Enum.any?(updated["services"], fn service ->
             service["name"] == "MCP"
           end)

    assert [%{"endpoint" => "new.eth", "name" => "ENS", "version" => "v1"}] =
             Enum.filter(updated["services"], &(&1["name"] == "ENS"))
  end

  test "prepares an updated registration and publishes a replacement uri" do
    assert {:ok, prepared} =
             Registration.prepare_updated_registration(%{
               current_agent_uri: "https://example.invalid/agent.json",
               ens_name: "new.eth",
               fetcher: StaticFetcher,
               publisher: EchoPublisher
             })

    assert prepared.changed?

    assert prepared.new_registration["type"] ==
             "https://eips.ethereum.org/EIPS/eip-8004#registration-v1"

    assert [%{"endpoint" => "new.eth", "name" => "ENS", "version" => "v1"}] =
             Enum.filter(prepared.new_registration["services"], &(&1["name"] == "ENS"))

    assert String.starts_with?(prepared.new_uri, "data:application/json,")
  end

  test "parses a data uri payload" do
    payload =
      "data:application/json," <>
        URI.encode_www_form(
          ~s({"type":"https://eips.ethereum.org/EIPS/eip-8004#registration-v1"})
        )

    assert {:ok, %{"type" => "https://eips.ethereum.org/EIPS/eip-8004#registration-v1"}} =
             Registration.parse_registration(payload)
  end

  test "rejects unsupported registration content types" do
    assert {:error, %Error{kind: :invalid_argument, message: message}} =
             Registration.parse_registration("data:text/plain,hello")

    assert message =~ "invalid data URI"
  end

  test "rejects unsupported base64 registration content types" do
    payload =
      "data:text/plain;base64," <>
        Base.encode64(~s({"type":"https://eips.ethereum.org/EIPS/eip-8004#registration-v1"}))

    assert {:error, %Error{kind: :invalid_argument, message: message}} =
             Registration.parse_registration(payload)

    assert message =~ "invalid data URI"
  end
end
