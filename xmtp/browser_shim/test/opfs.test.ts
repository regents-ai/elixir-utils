import { describe, expect, it, vi } from "vitest";
import { Opfs, type OpfsTransport } from "../src/opfs";

class FakeWorker {
  listeners = new Map<string, Set<(event: MessageEvent<any>) => void>>();
  messages: unknown[] = [];
  terminated = false;

  constructor(public url: URL, public options: { type: string }) {}

  addEventListener(type: string, listener: (event: MessageEvent<any>) => void) {
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener);
    this.listeners.set(type, listeners);
  }

  removeEventListener(
    type: string,
    listener: (event: MessageEvent<any>) => void,
  ) {
    this.listeners.get(type)?.delete(listener);
  }

  postMessage(message: unknown) {
    this.messages.push(message);
    const request = message as { action?: string; id?: string };
    if (request.action === "opfs.init") {
      queueMicrotask(() => {
        for (const listener of this.listeners.get("message") ?? []) {
          listener({
            data: {
              action: "opfs.init",
              id: request.id,
              result: undefined,
            },
          } as MessageEvent<any>);
        }
      });
    }
  }

  terminate() {
    this.terminated = true;
  }
}

describe("Opfs", () => {
  it("forwards browser storage actions through the transport", async () => {
    const calls: Array<{ action: string; data: unknown }> = [];
    const close = vi.fn();
    const transport: OpfsTransport = {
      action: (async (action: string, data?: unknown) => {
        calls.push({ action, data });
      }) as OpfsTransport["action"],
      close,
    };

    const opfs = new Opfs(transport);

    await opfs.init(true);
    await opfs.listFiles();
    await opfs.fileCount();
    await opfs.poolCapacity();
    await opfs.fileExists("db.sqlite");
    await opfs.deleteFile("db.sqlite");
    await opfs.exportDb("db.sqlite");
    await opfs.importDb("db.sqlite", new Uint8Array([1, 2, 3]));
    await opfs.clearAll();
    opfs.close();

    expect(calls.map(({ action }) => action)).toEqual([
      "opfs.init",
      "opfs.listFiles",
      "opfs.fileCount",
      "opfs.poolCapacity",
      "opfs.fileExists",
      "opfs.deleteFile",
      "opfs.exportDb",
      "opfs.importDb",
      "opfs.clearAll",
    ]);
    expect(calls[0]?.data).toEqual({ enableLogging: true });
    expect(calls[4]?.data).toEqual({ path: "db.sqlite" });
    expect(calls[7]?.data).toEqual({
      path: "db.sqlite",
      data: new Uint8Array([1, 2, 3]),
    });
    expect(close).toHaveBeenCalledOnce();
  });

  it("propagates transport failures for import and export", async () => {
    const failure = new Error("opfs failed");
    const transport: OpfsTransport = {
      action: (async (action: string) => {
        if (action === "opfs.exportDb" || action === "opfs.importDb") {
          throw failure;
        }
        return undefined;
      }) as OpfsTransport["action"],
      close: vi.fn(),
    };

    const opfs = new Opfs(transport);

    await expect(opfs.exportDb("missing.db3")).rejects.toBe(failure);
    await expect(
      opfs.importDb("missing.db3", new Uint8Array([1, 2, 3])),
    ).rejects.toBe(failure);
  });

  it("propagates initialization failures", async () => {
    const failure = new Error("not initialized");
    const transport: OpfsTransport = {
      action: (async () => {
        throw failure;
      }) as OpfsTransport["action"],
      close: vi.fn(),
    };

    const opfs = new Opfs(transport);

    await expect(opfs.init()).rejects.toBe(failure);
  });

  it("creates and initializes the worker-backed adapter", async () => {
    let worker: FakeWorker | undefined;
    class TestWorker extends FakeWorker {
      constructor(url: URL, options: { type: string }) {
        super(url, options);
        worker = this;
      }
    }

    vi.stubGlobal("Worker", TestWorker as any);

    const opfs = await Opfs.create(true);
    opfs.close();

    expect(worker).toBeDefined();
    expect(worker?.messages[0]).toMatchObject({
      action: "opfs.init",
      data: { enableLogging: true },
    });
    expect(worker?.terminated).toBe(true);

    vi.unstubAllGlobals();
  });
});
