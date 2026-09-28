defmodule RegentChain.TypedTest do
  use ExUnit.Case, async: true

  alias RegentChain.Typed

  # The example in EIP-712 itself, signed by the key keccak256("cow").
  @mail %{
    "types" => %{
      "EIP712Domain" => [
        %{"name" => "name", "type" => "string"},
        %{"name" => "version", "type" => "string"},
        %{"name" => "chainId", "type" => "uint256"},
        %{"name" => "verifyingContract", "type" => "address"}
      ],
      "Person" => [
        %{"name" => "name", "type" => "string"},
        %{"name" => "wallet", "type" => "address"}
      ],
      "Mail" => [
        %{"name" => "from", "type" => "Person"},
        %{"name" => "to", "type" => "Person"},
        %{"name" => "contents", "type" => "string"}
      ]
    },
    "primaryType" => "Mail",
    "domain" => %{
      "name" => "Ether Mail",
      "version" => "1",
      "chainId" => 1,
      "verifyingContract" => "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
    },
    "message" => %{
      "from" => %{"name" => "Cow", "wallet" => "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},
      "to" => %{"name" => "Bob", "wallet" => "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},
      "contents" => "Hello, Bob!"
    }
  }
  @mail_digest "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2"
  @mail_rs "4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b91562"
  @cow "0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826"

  # Arrays of structs, fixed arrays, int, bytes4, bytes and the zero address,
  # signed with `cast wallet sign --data` by the same key.
  @order %{
    "types" => %{
      "EIP712Domain" => [
        %{"name" => "name", "type" => "string"},
        %{"name" => "chainId", "type" => "uint256"},
        %{"name" => "verifyingContract", "type" => "address"},
        %{"name" => "salt", "type" => "bytes32"}
      ],
      "Asset" => [
        %{"name" => "token", "type" => "address"},
        %{"name" => "amounts", "type" => "uint128[]"}
      ],
      "Order" => [
        %{"name" => "maker", "type" => "address"},
        %{"name" => "assets", "type" => "Asset[]"},
        %{"name" => "tags", "type" => "string[2]"},
        %{"name" => "delta", "type" => "int64"},
        %{"name" => "selector", "type" => "bytes4"},
        %{"name" => "payload", "type" => "bytes"},
        %{"name" => "live", "type" => "bool"},
        %{"name" => "nobody", "type" => "address"}
      ]
    },
    "primaryType" => "Order",
    "domain" => %{
      "name" => "Regent",
      "chainId" => 8453,
      "verifyingContract" => "0x1111111111111111111111111111111111111111",
      "salt" => "0x00000000000000000000000000000000000000000000000000000000000000aa"
    },
    "message" => %{
      "maker" => "0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826",
      "assets" => [
        %{
          "token" => "0x2222222222222222222222222222222222222222",
          "amounts" => ["1", "340282366920938463463374607431768211455"]
        },
        %{"token" => "0x3333333333333333333333333333333333333333", "amounts" => []}
      ],
      "tags" => ["first", "second"],
      "delta" => "-42",
      "selector" => "0x095ea7b3",
      "payload" => "0xdeadbeef",
      "live" => true,
      "nobody" => "0x0000000000000000000000000000000000000000"
    }
  }
  @order_signature "0xb7c1476e9cca3fa3ec17bad05e1a2dd3dbc3e5e6c6cd29be16b474672b46c5541884b857cb6192beedd70611d925b7f1f4171114311a2af02a236fc1c06f97fc1c"

  test "the digest of the EIP-712 example" do
    assert Typed.digest(@mail) == {:ok, Base.decode16!(@mail_digest, case: :lower)}
  end

  test "recovers the signer, with v as 27 or 28 or as 0 or 1" do
    assert Typed.signer(@mail, "0x" <> @mail_rs <> "1c") == {:ok, @cow}
    assert Typed.signer(@mail, "0x" <> @mail_rs <> "01") == {:ok, @cow}
    assert Typed.signer(@order, @order_signature) == {:ok, @cow}
  end

  test "gives a signature as contracts take it" do
    assert Typed.signature("0x" <> String.upcase(@mail_rs) <> "01") ==
             {:ok, "0x" <> @mail_rs <> "1c"}

    assert Typed.signature("0x" <> @mail_rs <> "00") == {:ok, "0x" <> @mail_rs <> "1b"}
    assert Typed.signature("0x" <> @mail_rs <> "02") == :error
  end

  test "other terms recover someone else" do
    changed = put_in(@mail, ["message", "contents"], "Hello, Alice!")

    assert {:ok, other} = Typed.signer(changed, "0x" <> @mail_rs <> "1c")
    refute other == @cow
  end

  test "is :error for a value its type cannot hold" do
    assert Typed.digest(put_in(@order, ["message", "delta"], "9223372036854775808")) == :error
    assert Typed.digest(put_in(@order, ["message", "tags"], ["only one"])) == :error
    assert Typed.digest(put_in(@order, ["message", "selector"], "0x095ea7")) == :error
    assert Typed.digest(update_in(@order, ["message"], &Map.delete(&1, "live"))) == :error
  end
end
