defmodule Siwa.FixtureCaptchaTest do
  use ExUnit.Case, async: true

  test "unpacks and verifies the frozen JS captcha failure case" do
    fixture = Siwa.TestFixtures.load("captcha")
    data = fixture["case"]

    assert {:ok, unpacked} = Siwa.Captcha.unpack_response(data["packedResponse"])
    assert unpacked.challenge_token == data["unpacked"]["challengeToken"]
    assert unpacked.solution["text"] == data["unpacked"]["solution"]["text"]
    assert unpacked.solution["solvedAt"] == data["unpacked"]["solution"]["solvedAt"]

    assert {:ok, verified} =
             Siwa.Captcha.verify_challenge(
               data["challengeToken"],
               data["unpacked"]["solution"],
               "fixture-secret",
               timing_tolerance_seconds: 2
             )

    assert verified.verdict == data["verified"]["verdict"]
    assert verified.overallPass == data["verified"]["overallPass"]
    assert verified.asciiSum.actual == data["verified"]["asciiSum"]["actual"]
    assert verified.asciiSum.target == data["verified"]["asciiSum"]["target"]
    assert verified.lineCount.actual == data["verified"]["lineCount"]["actual"]
    assert verified.wordCount.actual == data["verified"]["wordCount"]["actual"]
  end
end
