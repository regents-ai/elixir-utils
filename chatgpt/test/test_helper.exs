ExUnit.start()

defmodule RegentChatGPT.TestSupport do
  def jwt(claims) do
    header = %{"alg" => "none", "typ" => "JWT"} |> Jason.encode!() |> b64()
    payload = claims |> Jason.encode!() |> b64()
    "#{header}.#{payload}.sig"
  end

  defp b64(value), do: Base.url_encode64(value, padding: false)
end
