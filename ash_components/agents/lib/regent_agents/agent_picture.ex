defmodule RegentAgents.AgentPicture.WebP do
  @moduledoc """
  The picture is a WebP file of at most #{65_536} bytes, judged by its first
  bytes ("RIFF", four bytes of length, "WEBP"). regents.sh re-makes every
  upload as a 256 by 256 WebP before it gets here.
  """
  use Ash.Resource.Validation

  @max_bytes 65_536

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :bytes) do
      <<"RIFF", _length::binary-size(4), "WEBP", _rest::binary>> = bytes
      when byte_size(bytes) <= @max_bytes ->
        :ok

      <<"RIFF", _length::binary-size(4), "WEBP", _rest::binary>> ->
        {:error, field: :bytes, message: "must be at most #{@max_bytes} bytes"}

      _other ->
        {:error, field: :bytes, message: "must be a WebP picture"}
    end
  end
end

defmodule RegentAgents.AgentPicture do
  @moduledoc """
  The picture a person chose for one of their paired agents, shown beside what
  the agent posts on every Regent site. The person sets and removes it on
  regents.sh/account; a team member (`RegentAgents.Checks.Admin`) may only
  remove it. Unpairing the agent removes its picture with it.

  Anyone may read a picture: every site serves it at
  `/agents/<wallet>/picture`. `RegentAgents.PairedAgent`'s
  `picture_updated_at` says whether an agent has one without reading its bytes.
  """

  use Ash.Resource,
    otp_app: :regent_agents,
    domain: RegentAgents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentAgents.repo/2
    schema "regent_agents"
    table "agent_pictures"
    migrate? false
  end

  attributes do
    attribute :bytes, :binary, allow_nil?: false
    attribute :updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :paired_agent, RegentAgents.PairedAgent do
      primary_key? true
      allow_nil? false
      attribute_writable? true
    end
  end

  actions do
    read :read do
      primary? true
    end

    read :by_wallet do
      get? true
      argument :wallet, :string, allow_nil?: false
      filter expr(paired_agent.wallet == ^arg(:wallet))
    end

    create :set do
      accept [:paired_agent_id, :bytes]
      upsert? true
      upsert_fields [:bytes, :updated_at]
      validate RegentAgents.AgentPicture.WebP
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    destroy :remove

    destroy :remove_by_team
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:set) do
      authorize_if RegentAgents.Checks.OwnsAgent
    end

    policy action(:remove) do
      authorize_if RegentAgents.Checks.Person
    end

    policy action(:remove) do
      authorize_if expr(paired_agent.privy_user_id == ^actor(:privy_user_id))
    end

    policy action(:remove_by_team) do
      authorize_if RegentAgents.Checks.Admin
    end
  end
end
