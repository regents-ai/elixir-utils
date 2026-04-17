defmodule XmtpElixirSdk.Client do
  @moduledoc """
  Plain XMTP client data.
  """

  alias XmtpElixirSdk.Types

  defstruct [
    :runtime,
    :id,
    :identifier,
    :inbox_id,
    :installation_id,
    :installation_id_bytes,
    :options,
    :signer,
    :ready?,
    :app_version,
    :env,
    :libxmtp_version,
    :account_identifiers,
    :recovery_identifier,
    :registered?
  ]

  @type t :: %__MODULE__{
          runtime: atom(),
          id: String.t(),
          identifier: Types.Identifier.t(),
          inbox_id: String.t(),
          installation_id: String.t(),
          installation_id_bytes: binary(),
          options: keyword(),
          signer: map() | nil,
          ready?: boolean(),
          app_version: String.t(),
          env: Types.env(),
          libxmtp_version: String.t(),
          account_identifiers: [Types.Identifier.t()] | nil,
          recovery_identifier: Types.Identifier.t() | nil,
          registered?: boolean() | nil
        }

  @spec from_record(atom(), map()) :: t()
  def from_record(runtime, record) do
    %__MODULE__{
      runtime: runtime,
      id: record.id,
      identifier: record.identifier,
      inbox_id: record.inbox_id,
      installation_id: record.installation_id,
      installation_id_bytes: record.installation_id_bytes,
      options: Map.get(record, :options, []),
      signer: Map.get(record, :signer),
      ready?: Map.get(record, :registered?, true),
      app_version: record.app_version,
      env: record.env,
      libxmtp_version: record.libxmtp_version,
      account_identifiers: Map.get(record, :account_identifiers),
      recovery_identifier: Map.get(record, :recovery_identifier),
      registered?: Map.get(record, :registered?)
    }
  end
end
