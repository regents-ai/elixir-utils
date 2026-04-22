defmodule Mix.Tasks.Compile.XmtpCompat do
  use Mix.Task.Compiler

  @recursive true
  @shortdoc "Copies recovered XMTP compatibility beams into the compile output"

  @impl true
  def run(_args) do
    source_glob = Path.join(File.cwd!(), "compat_ebin/*.beam")
    source_paths = Path.wildcard(source_glob)

    if source_paths == [] do
      {:noop, []}
    else
      compile_path = Mix.Project.compile_path()
      File.mkdir_p!(compile_path)

      Enum.each(source_paths, fn source_path ->
        File.cp!(source_path, Path.join(compile_path, Path.basename(source_path)))
      end)

      Mix.shell().info("Copied #{length(source_paths)} XMTP compatibility beams")
      {:ok, []}
    end
  end
end
