import Config

default_keystore_path = Path.expand("../harness/agent-keystore.bin", __DIR__)

required_prod_env = fn name, default ->
  if config_env() == :prod do
    System.fetch_env!(name)
  else
    System.get_env(name, default)
  end
end

config :siwa,
  receipt_secret: required_prod_env.("SIWA_RECEIPT_SECRET", "siwa-dev-receipt-secret")

config :siwa_keyring,
  backend: System.get_env("KEYSTORE_BACKEND", "encrypted_file"),
  password: required_prod_env.("KEYSTORE_PASSWORD", "change-me"),
  path:
    required_prod_env.(
      "KEYSTORE_PATH",
      default_keystore_path
    )
