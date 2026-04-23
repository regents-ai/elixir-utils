import Config

config :siwa,
  nonce_store: Siwa.Nonce.MemoryStore,
  receipt_secret: System.get_env("SIWA_RECEIPT_SECRET", "siwa-dev-receipt-secret"),
  nonce_secret: System.get_env("SIWA_NONCE_SECRET", "siwa-dev-nonce-secret")

config :siwa_keyring,
  secret: System.get_env("KEYRING_PROXY_SECRET", "siwa-dev-keyring-secret"),
  port: String.to_integer(System.get_env("KEYRING_PROXY_PORT", "3100")),
  backend: System.get_env("KEYSTORE_BACKEND", "encrypted_file"),
  password: System.get_env("KEYSTORE_PASSWORD", "change-me"),
  path:
    System.get_env(
      "KEYSTORE_PATH",
      "/Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir/harness/agent-keystore.bin"
    ),
  host: System.get_env("KEYRING_PROXY_HOST", "127.0.0.1")
