defmodule Siwa.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Siwa.Nonce.MemoryStore, name: Siwa.Nonce.MemoryStore},
      {Siwa.RequestAuth.ReplayStore, name: Siwa.RequestAuth.ReplayStore}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Siwa.Supervisor)
  end
end
