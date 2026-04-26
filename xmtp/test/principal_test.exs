defmodule Xmtp.PrincipalTest do
  use ExUnit.Case, async: true

  alias Xmtp.Principal

  test "from/1 accepts only current principal fields from string-key maps" do
    unknown_key = "unexpected_principal_key_#{System.unique_integer([:positive])}"

    principal =
      Principal.from(%{
        "kind" => "agent",
        "wallet_address" => " 0xABC0000000000000000000000000000000000001 ",
        "display_name" => " Launch Agent ",
        unknown_key => "ignored"
      })

    assert principal.kind == :agent
    assert principal.wallet_address == "0xabc0000000000000000000000000000000000001"
    assert principal.display_name == "Launch Agent"

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(unknown_key)
    end
  end
end
