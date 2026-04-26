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
    :registered?,
    :native?
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
          registered?: boolean() | nil,
          native?: boolean() | nil
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
      registered?: Map.get(record, :registered?),
      native?: Map.get(record, :native?)
    }
  end

  @spec from_native_record(atom(), map(), keyword()) :: t()
  def from_native_record(runtime, record, opts \\ []) do
    identifier = %Types.Identifier{
      identifier: Map.fetch!(record, "account_identifier"),
      identifier_kind: :ethereum
    }

    installation_id_bytes =
      record
      |> Map.get("installation_id_bytes", "")
      |> String.trim_leading("0x")
      |> Base.decode16!(case: :mixed)

    %__MODULE__{
      runtime: runtime,
      id: Map.fetch!(record, "id"),
      identifier: identifier,
      inbox_id: Map.fetch!(record, "inbox_id"),
      installation_id: Map.fetch!(record, "installation_id"),
      installation_id_bytes: installation_id_bytes,
      options: opts,
      signer: nil,
      ready?: Map.get(record, "registered", true),
      app_version: Map.get(record, "app_version"),
      env: Keyword.get(opts, :env, :dev),
      libxmtp_version: Map.get(record, "libxmtp_version"),
      account_identifiers: [identifier],
      recovery_identifier: identifier,
      registered?: Map.get(record, "registered"),
      native?: true
    }
  end
end
