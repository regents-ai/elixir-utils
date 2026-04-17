defmodule SiwaKeyringTest do
  use ExUnit.Case, async: true

  test "service module exists" do
    assert Code.ensure_loaded?(SiwaKeyring)
  end
end
