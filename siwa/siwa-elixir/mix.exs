defmodule SiwaElixir.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.1",
      start_permanent: Mix.env() == :prod,
      deps: [],
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test, precommit: :test]
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "contract.check",
        "test"
      ],
      precommit: ["check"],
      "contract.check": ["run --no-start scripts/check_shared_services_contract.exs"]
    ]
  end
end
