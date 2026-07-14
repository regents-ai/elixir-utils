defmodule RegentChatGPT.DeviceCode do
  @moduledoc "Pending ChatGPT device-code authorization state."

  @enforce_keys [:device_auth_id, :user_code, :verification_url, :interval, :expires_at]
  defstruct [:device_auth_id, :user_code, :verification_url, :interval, :expires_at]

  @type t :: %__MODULE__{
          device_auth_id: String.t(),
          user_code: String.t(),
          verification_url: String.t(),
          interval: pos_integer(),
          expires_at: integer()
        }
end
