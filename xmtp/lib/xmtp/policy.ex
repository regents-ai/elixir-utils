defmodule Xmtp.Policy do
  @moduledoc false

  alias Xmtp.Principal
  alias Xmtp.RoomDefinition

  @callback allow_join(RoomDefinition.t(), Principal.t(), map()) ::
              :ok | {:error, atom()}
end
