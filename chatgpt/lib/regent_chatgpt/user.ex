defmodule RegentChatGPT.User do
  @moduledoc "Public ChatGPT account profile derived from the id token."

  @enforce_keys [:account_id]
  defstruct [:account_id, :email, :name, :plan]

  @type t :: %__MODULE__{
          account_id: String.t(),
          email: String.t() | nil,
          name: String.t() | nil,
          plan: String.t() | nil
        }
end
