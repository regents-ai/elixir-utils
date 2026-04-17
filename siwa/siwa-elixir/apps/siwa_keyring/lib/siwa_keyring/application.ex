defmodule SiwaKeyring.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        []
      else
        port = Application.fetch_env!(:siwa_keyring, :port)
        host = Application.fetch_env!(:siwa_keyring, :host) |> to_ip()
        [{Bandit, plug: SiwaKeyring.Router, scheme: :http, port: port, ip: host}]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: SiwaKeyring.Supervisor)
  end

  defp to_ip(host) when is_binary(host) do
    host
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end
end
