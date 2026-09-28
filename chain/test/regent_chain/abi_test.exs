defmodule RegentChain.AbiTest do
  use ExUnit.Case, async: true

  alias RegentChain.Abi

  # `cast abi-encode "f(bool,uint64[],bytes32,bytes)" true "[3,5]" 0x…ff 0xdeadbeef`
  @mixed "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000ff00000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000004deadbeef00000000000000000000000000000000000000000000000000000000"
  @mixed_types [:bool, {:array, {:uint, 64}}, :bytes32, :bytes]

  # `cast abi-encode "f(address,string)" 0x1111111111111111111111111111111111111111 "hi"`
  @named "0x0000000000000000000000001111111111111111111111111111111111111111000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000026869000000000000000000000000000000000000000000000000000000000000"

  defp data(hex) do
    {:ok, bytes} = Abi.bytes(hex)
    bytes
  end

  describe "decode/2" do
    test "reads static and dynamic values in order" do
      assert Abi.decode(data(@mixed), @mixed_types) ==
               {:ok,
                [
                  true,
                  [3, 5],
                  "0x" <> String.pad_leading("ff", 64, "0"),
                  <<0xDE, 0xAD, 0xBE, 0xEF>>
                ]}

      assert Abi.decode(data(@named), [:address, :bytes]) ==
               {:ok, ["0x1111111111111111111111111111111111111111", "hi"]}
    end

    test "is :error for anything but the canonical encoding" do
      bytes = data(@named)

      assert Abi.decode(bytes <> <<0::256>>, [:address, :bytes]) == :error

      assert Abi.decode(binary_part(bytes, 0, byte_size(bytes) - 32), [:address, :bytes]) ==
               :error

      assert Abi.decode(bytes, [:address, :bytes, :bool]) == :error

      <<head::binary-size(32), _offset::256, rest::binary>> = bytes
      assert Abi.decode(head <> <<0x60::256>> <> rest, [:address, :bytes]) == :error

      <<body::binary-size(byte_size(bytes) - 1), _last>> = bytes
      assert Abi.decode(body <> <<1>>, [:address, :bytes]) == :error
    end

    test "bounds an integer by the bits it is read as" do
      assert Abi.decode(<<255::256>>, [{:uint, 8}]) == {:ok, [255]}
      assert Abi.decode(<<256::256>>, [{:uint, 8}]) == :error
    end
  end

  describe "word/2" do
    test "reads a topic as an address only when its leading twelve bytes are zero" do
      assert Abi.word(<<0::96, 0x11::160>>, :address) ==
               {:ok, "0x0000000000000000000000000000000000000011"}

      assert Abi.word(<<1::96, 0x11::160>>, :address) == :error
      assert Abi.word(<<2::256>>, :bool) == :error
    end
  end

  test "reads JSON-RPC quantities, hashes and data" do
    assert Abi.quantity("0x1a") == {:ok, 26}
    assert Abi.quantity("0x") == :error

    assert Abi.hash("0x" <> String.duplicate("AB", 32)) ==
             {:ok, "0x" <> String.duplicate("ab", 32)}

    assert Abi.hash("0xab") == :error
    assert Abi.bytes("0x") == {:ok, ""}
    assert Abi.bytes("0xabc") == :error
  end
end
