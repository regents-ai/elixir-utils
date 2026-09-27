defmodule Mix.Tasks.RegentErc8004.Assets do
  @moduledoc "Copies the ERC-8004 domain stylesheet into the invoking project's assets/vendor directory."
  use Mix.Task
  @shortdoc "Stage the ERC-8004 stylesheet (no JavaScript)"

  @impl true
  def run([]) do
    source = Path.join(:code.priv_dir(:regent_erc8004), "static/erc8004.css")
    target = Path.expand("assets/vendor/regent_erc8004/erc8004.css")
    File.mkdir_p!(Path.dirname(target))
    File.cp!(source, target)
    Mix.shell().info("Staged ERC-8004 CSS to #{target}")
  end

  def run(_args), do: Mix.raise("Usage: mix regent_erc8004.assets")
end
