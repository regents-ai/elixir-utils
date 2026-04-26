defmodule Xmtp.RoomDefinition do
  @moduledoc false

  alias Xmtp.Policy.Default

  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          description: String.t() | nil,
          app_data: String.t() | nil,
          agent_private_key: String.t() | nil,
          moderator_wallets: [String.t()],
          capacity: pos_integer(),
          presence_timeout_ms: pos_integer(),
          presence_check_interval_ms: pos_integer(),
          policy_module: module(),
          policy_options: map()
        }

  defstruct key: nil,
            name: nil,
            description: nil,
            app_data: nil,
            agent_private_key: nil,
            moderator_wallets: [],
            capacity: 200,
            presence_timeout_ms: :timer.minutes(2),
            presence_check_interval_ms: :timer.seconds(30),
            policy_module: Default,
            policy_options: %{}

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    attrs = Enum.into(attrs, %{})

    %__MODULE__{
      key: Map.fetch!(attrs, :key),
      name: Map.fetch!(attrs, :name),
      description: Map.get(attrs, :description),
      app_data: Map.get(attrs, :app_data),
      agent_private_key: Map.get(attrs, :agent_private_key),
      moderator_wallets: Map.get(attrs, :moderator_wallets, []),
      capacity: Map.get(attrs, :capacity, 200),
      presence_timeout_ms: Map.get(attrs, :presence_timeout_ms, :timer.minutes(2)),
      presence_check_interval_ms: Map.get(attrs, :presence_check_interval_ms, :timer.seconds(30)),
      policy_module: Map.get(attrs, :policy_module, Default),
      policy_options: Map.get(attrs, :policy_options, %{})
    }
  end
end
