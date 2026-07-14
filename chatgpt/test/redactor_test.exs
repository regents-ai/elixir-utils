defmodule RegentChatGPT.RedactorTest do
  use ExUnit.Case, async: true

  alias RegentChatGPT.Redactor

  test "redacts ChatGPT tokens and headers from strings" do
    message =
      ~s({"access_token":"access-secret","refresh_token":"refresh-secret","id_token":"id-secret","authorization":"Bearer bearer-secret","chatgpt-account-id":"acct-secret"})

    redacted = Redactor.redact(message)

    assert redacted =~ "[redacted]"
    refute redacted =~ "access-secret"
    refute redacted =~ "refresh-secret"
    refute redacted =~ "id-secret"
    refute redacted =~ "bearer-secret"
    refute redacted =~ "acct-secret"
  end
end
