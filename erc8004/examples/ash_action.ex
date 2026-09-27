# Optional product-side example: requires Ash, not compiled into regent_erc8004.
# Deliberately public indexed evidence. Replace this policy with the product's
# authorization, rate limits and tenant-aware configured-client selection.

defmodule RegentERC8004.Example.ReadEvidence do
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, _context) do
    client = Application.fetch_env!(:erc8004_example, :client)

    case RegentERC8004.Client.load(client, input.arguments.agent_id) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, _reason} -> {:error, "Indexed agent evidence could not be loaded."}
    end
  end
end

defmodule RegentERC8004.Example.Agent do
  use Ash.Resource, domain: RegentERC8004.Example.Domain, authorizers: [Ash.Policy.Authorizer]

  actions do
    action :evidence, :struct do
      constraints(instance_of: RegentERC8004.Snapshot)

      argument :agent_id, :string do
        allow_nil?(false)
        constraints(trim?: false, max_length: 78)
      end

      run(RegentERC8004.Example.ReadEvidence)
    end
  end

  policies do
    policy action(:evidence) do
      authorize_if(always())
    end
  end
end

defmodule RegentERC8004.Example.Domain do
  use Ash.Domain

  resources do
    resource(RegentERC8004.Example.Agent)
  end
end
