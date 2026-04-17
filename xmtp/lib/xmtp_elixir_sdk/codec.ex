defmodule XmtpElixirSdk.Codec do
  @moduledoc """
  Behaviour for custom content codecs.
  """

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types.ContentTypeId

  @callback content_type() :: ContentTypeId.t()
  @callback encode(term()) :: {:ok, term()} | {:error, Error.t()}
  @callback decode(term()) :: {:ok, term()} | {:error, Error.t()}
end
