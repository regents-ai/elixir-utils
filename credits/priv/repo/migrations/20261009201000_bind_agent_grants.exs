defmodule RegentCredits.Migrations.BindAgentGrants do
  use Ecto.Migration

  def up do
    alter table(:agent_permissions, prefix: "regent_credits") do
      add(:pairing_id, :uuid)
    end

    alter table(:holds, prefix: "regent_credits") do
      add(:pairing_id, :uuid)
    end

    # Existing grants lack provable episode binding. Preserve their settings for
    # investigation and account-owner reapproval; never infer ownership by wallet.
    execute(
      "UPDATE regent_credits.agent_permissions SET enabled = false WHERE pairing_id IS NULL"
    )

    create constraint(:agent_permissions, :enabled_requires_pairing,
             prefix: "regent_credits",
             check: "NOT enabled OR pairing_id IS NOT NULL"
           )

    execute("""
    CREATE FUNCTION regent_credits.revoke_pairing_grant() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        UPDATE regent_credits.agent_permissions SET enabled = false
        WHERE pairing_id = OLD.id;
      END IF;
      RETURN OLD;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER revoke_credit_grant AFTER DELETE
    ON regent_agents.paired_agents FOR EACH ROW
    EXECUTE FUNCTION regent_credits.revoke_pairing_grant()
    """)
  end

  def down do
    raise "Preserve episode-bound grants and attribution; use a forward repair"
  end
end
