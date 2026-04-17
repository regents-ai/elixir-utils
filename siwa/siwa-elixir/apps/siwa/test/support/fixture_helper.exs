defmodule Siwa.TestFixtures do
  def load(name) do
    path = Path.expand("../../../../fixtures/siwa/#{name}.json", __DIR__)
    path |> File.read!() |> Jason.decode!()
  end
end
