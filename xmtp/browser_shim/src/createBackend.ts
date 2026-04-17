import type { ClientOptions, XmtpEnv } from "./contracts";

export type BackendConfig = {
  env: number;
  appVersion?: string;
  apiUrl?: string;
  gatewayHost?: string;
  xmtpEnv: XmtpEnv;
};

const envMap: Record<XmtpEnv, number> = {
  local: 0,
  dev: 1,
  production: 2,
  "testnet-staging": 3,
  "testnet-dev": 4,
  testnet: 5,
  mainnet: 6,
};

const reverseEnvMap: Record<number, XmtpEnv> = {
  0: "local",
  1: "dev",
  2: "production",
  3: "testnet-staging",
  4: "testnet-dev",
  5: "testnet",
  6: "mainnet",
};

export const envToString = (env: number): XmtpEnv => {
  return reverseEnvMap[env];
};

export const createBackend = async (
  options?: Pick<ClientOptions, "env" | "apiUrl" | "gatewayHost" | "appVersion">,
): Promise<BackendConfig> => {
  const xmtpEnv = options?.env ?? "dev";

  return {
    env: envMap[xmtpEnv],
    xmtpEnv,
    appVersion: options?.appVersion,
    apiUrl: options?.apiUrl,
    gatewayHost: options?.gatewayHost,
  };
};
