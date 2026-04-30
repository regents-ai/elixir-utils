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
  nonce_store: Siwa.Nonce.MemoryStore,
  receipt_secret: required_prod_env.("SIWA_RECEIPT_SECRET", "siwa-dev-receipt-secret"),
  nonce_secret: required_prod_env.("SIWA_NONCE_SECRET", "siwa-dev-nonce-secret")

config :siwa_keyring,
  secret: required_prod_env.("KEYRING_PROXY_SECRET", "siwa-dev-keyring-secret"),
  port: String.to_integer(System.get_env("KEYRING_PROXY_PORT", "3100")),
  start_server: config_env() != :test,
  backend: System.get_env("KEYSTORE_BACKEND", "encrypted_file"),
  password: required_prod_env.("KEYSTORE_PASSWORD", "change-me"),
  path:
    required_prod_env.(
      "KEYSTORE_PATH",
      default_keystore_path
    ),
  host: System.get_env("KEYRING_PROXY_HOST", "127.0.0.1")
