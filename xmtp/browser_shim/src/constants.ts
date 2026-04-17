import type { XmtpEnv } from "./contracts";

export const ApiUrls = {
  local: "http://localhost:5557",
  dev: "https://api.dev.xmtp.network:5558",
  production: "https://api.production.xmtp.network:5558",
} as const satisfies Record<Extract<XmtpEnv, "local" | "dev" | "production">, string>;

export const HistorySyncUrls = {
  local: "http://localhost:5558",
  dev: "https://message-history.dev.ephemera.network",
  production: "https://message-history.production.ephemera.network",
  "testnet-staging": "https://message-history.dev.ephemera.network",
  "testnet-dev": "https://message-history.dev.ephemera.network",
  testnet: "https://message-history.dev.ephemera.network",
  mainnet: "https://message-history.production.ephemera.network",
} as const satisfies Record<XmtpEnv, string>;
