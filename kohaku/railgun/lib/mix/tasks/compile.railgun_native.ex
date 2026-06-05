defmodule Mix.Tasks.Compile.RailgunNative do
  use Mix.Task.Compiler

  @recursive true
  @shortdoc "Builds the native Railgun bridge"
  @manifest Path.expand("../../../native/railgun_native/Cargo.toml", __DIR__)

  @impl true
  def run(_args) do
    profile_args = if Mix.env() == :prod, do: ["--release"], else: []
    args = ["build", "--manifest-path", @manifest] ++ profile_args

    Mix.shell().info("Building Railgun native bridge")

    case System.cmd("cargo", args, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> maybe_info()

        {:ok, []}

      {output, status} ->
        Mix.raise("cargo build for Railgun native bridge failed with status #{status}\n#{output}")
    end
  end

  defp maybe_info(""), do: :ok
  defp maybe_info(output), do: Mix.shell().info(output)
end
