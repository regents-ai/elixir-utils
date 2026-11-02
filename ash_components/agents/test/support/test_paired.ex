defmodule RegentAgents.TestSite do
  @moduledoc "A stand-in for the site that listens to `RegentAgents.Signals`."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource RegentAgents.TestPaired
  end
end

defmodule RegentAgents.TestPaired do
  @moduledoc """
  A stand-in for the site's listener: tells the pairing process of each agent
  paired, and whether it heard inside the pairing's transaction.
  """
  use Ash.Resource, domain: RegentAgents.TestSite

  signals_in do
    from RegentAgents.Signals do
      on :agent_paired, :paired_heard, action: :heard
    end
  end

  actions do
    action :heard do
      argument :signal, :struct, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        send(
          self(),
          {:paired, signal.paired_agent_id, signal.privy_user_id,
           RegentAgents.TestRepo.in_transaction?()}
        )

        :ok
      end
    end
  end
end
