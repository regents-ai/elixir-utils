defmodule Mix.Tasks.Siwa.Contract do
  @shortdoc "Writes the signed request contract and its fixtures to siwa/contract/"
  @moduledoc """
  Writes `Siwa.Contract.json/0` to `siwa/contract/contract.json` and
  `Siwa.Contract.Fixtures.json/0` to `siwa/contract/fixtures.json` in the
  elixir-utils repository.

      mix siwa.contract          # write both files
      mix siwa.contract --check  # fail when either file differs from the library
  """

  use Mix.Task

  @requirements ["compile"]

  @impl Mix.Task
  def run(args) do
    {opts, _args} = OptionParser.parse!(args, strict: [check: :boolean])
    dir = Path.expand("../../../../../../contract", __DIR__)

    files = [
      {Path.join(dir, "contract.json"), Siwa.Contract.json()},
      {Path.join(dir, "fixtures.json"), Siwa.Contract.Fixtures.json()}
    ]

    if opts[:check], do: check(files), else: write(dir, files)
  end

  defp write(dir, files) do
    File.mkdir_p!(dir)

    for {path, content} <- files do
      File.write!(path, content)
      Mix.shell().info("Wrote #{Path.relative_to_cwd(path)}")
    end

    Mix.shell().info("Contract id #{Siwa.Contract.id()}")
  end

  defp check(files) do
    case Enum.reject(files, fn {path, content} -> File.read(path) == {:ok, content} end) do
      [] ->
        Mix.shell().info("Contract files match, id #{Siwa.Contract.id()}")

      stale ->
        Mix.raise(
          "Out of date: #{Enum.map_join(stale, ", ", &Path.relative_to_cwd(elem(&1, 0)))}. " <>
            "Run `mix siwa.contract` and commit the result."
        )
    end
  end
end
