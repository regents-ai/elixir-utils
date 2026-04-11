import { describe, expect, it } from "vitest";
import { createBackend, envToString } from "../src/createBackend";

describe("createBackend", () => {
  it("uses dev as the default environment", async () => {
    const backend = await createBackend();

    expect(backend).toMatchObject({
      env: 1,
      xmtpEnv: "dev",
    });
  });

  it("maps each environment to its numeric builder value", async () => {
    expect((await createBackend({ env: "local" })).env).toBe(0);
    expect((await createBackend({ env: "dev" })).env).toBe(1);
    expect((await createBackend({ env: "production" })).env).toBe(2);
    expect((await createBackend({ env: "testnet-staging" })).env).toBe(3);
    expect((await createBackend({ env: "testnet-dev" })).env).toBe(4);
    expect((await createBackend({ env: "testnet" })).env).toBe(5);
    expect((await createBackend({ env: "mainnet" })).env).toBe(6);
  });

  it("passes through app, api, and gateway overrides", async () => {
    const backend = await createBackend({
      env: "production",
      appVersion: "test/1.0.0",
      apiUrl: "https://custom-api.example.com:5558",
      gatewayHost: "https://my-gateway.example.com",
    });

    expect(backend).toMatchObject({
      env: 2,
      xmtpEnv: "production",
      appVersion: "test/1.0.0",
      apiUrl: "https://custom-api.example.com:5558",
      gatewayHost: "https://my-gateway.example.com",
    });
  });

  it("passes through appVersion on its own", async () => {
    const backend = await createBackend({ appVersion: "test/2.0.0" });

    expect(backend).toMatchObject({
      env: 1,
      xmtpEnv: "dev",
      appVersion: "test/2.0.0",
    });
  });

  it("passes through apiUrl and gatewayHost overrides independently", async () => {
    const backend = await createBackend({
      apiUrl: "https://custom-api.example.com:5558",
      gatewayHost: "https://my-gateway.example.com",
    });

    expect(backend).toMatchObject({
      env: 1,
      xmtpEnv: "dev",
      apiUrl: "https://custom-api.example.com:5558",
      gatewayHost: "https://my-gateway.example.com",
    });
  });

  it("maps builder values back to environment names", () => {
    expect(envToString(0)).toBe("local");
    expect(envToString(1)).toBe("dev");
    expect(envToString(2)).toBe("production");
    expect(envToString(3)).toBe("testnet-staging");
    expect(envToString(4)).toBe("testnet-dev");
    expect(envToString(5)).toBe("testnet");
    expect(envToString(6)).toBe("mainnet");
  });
});
