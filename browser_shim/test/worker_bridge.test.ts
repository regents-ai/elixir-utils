import { describe, expect, it, vi } from "vitest";
import { WorkerBridge } from "../src/WorkerBridge";
import type { ClientWorkerAction } from "../src/contracts";

class FakeWorker {
  listeners = new Map<string, Set<(event: MessageEvent<any>) => void>>();
  messages: unknown[] = [];
  terminated = false;

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
  }

  terminate() {
    this.terminated = true;
  }

  emit(type: string, data: unknown) {
    for (const listener of this.listeners.get(type) ?? []) {
      listener({ data } as MessageEvent<any>);
    }
  }
}

describe("WorkerBridge", () => {
  it("correlates worker actions with request ids", async () => {
    const worker = new FakeWorker();
    const bridge = new WorkerBridge<ClientWorkerAction>(worker as unknown as Worker);

    const promise = bridge.action("client.isRegistered");
    const request = worker.messages[0] as { action: string; id: string; data: undefined };

    expect(request.action).toBe("client.isRegistered");
    expect(request.data).toBeUndefined();

    worker.emit("message", {
      id: request.id,
      action: "client.isRegistered",
      result: true,
    });

    await expect(promise).resolves.toBe(true);
  });

  it("ends stream listeners through the worker boundary", async () => {
    const worker = new FakeWorker();
    const bridge = new WorkerBridge<ClientWorkerAction>(worker as unknown as Worker);
    const onValue = vi.fn();
    const close = vi.fn(() => undefined);

    const stop = bridge.handleStreamMessage(
      "stream-1",
      (error, value) => {
        expect(error).toBeNull();
        onValue(value);
      },
      { close },
    );

    worker.emit("message", {
      streamId: "stream-1",
      action: "stream.message",
      result: { id: "message-1" },
    });

    expect(onValue).toHaveBeenCalledWith({ id: "message-1" });

    const cleanup = stop();
    await Promise.resolve();
    const endStreamRequest = worker.messages.at(-1) as
      | { action: string; id: string; data: { streamId: string } }
      | undefined;

    expect(endStreamRequest?.action).toBe("endStream");
    expect(endStreamRequest?.data).toEqual({ streamId: "stream-1" });

    worker.emit("message", {
      id: endStreamRequest?.id,
      action: "endStream",
      result: undefined,
    });

    await cleanup;
    expect(close).toHaveBeenCalledOnce();
  });

  it("routes worker errors back to the caller and stream fail callbacks", async () => {
    const worker = new FakeWorker();
    const bridge = new WorkerBridge<ClientWorkerAction>(worker as unknown as Worker);
    const onFail = vi.fn();
    const callback = vi.fn();

    const stop = bridge.handleStreamMessage("stream-2", callback, {
      onFail,
      close: vi.fn(),
    });

    worker.emit("message", {
      streamId: "stream-2",
      action: "stream.fail",
      result: undefined,
    });

    expect(onFail).toHaveBeenCalledOnce();
    expect(callback).not.toHaveBeenCalled();

    worker.emit("message", {
      streamId: "stream-2",
      action: "stream.message",
      error: new Error("boom"),
    });

    expect(callback).toHaveBeenCalledWith(expect.any(Error), undefined);

    const cleanup = stop();
    await Promise.resolve();
    const endStreamRequest = worker.messages.at(-1) as
      | { action: string; id: string; data: { streamId: string } }
      | undefined;

    worker.emit("message", {
      id: endStreamRequest?.id,
      action: "endStream",
      result: undefined,
    });

    await cleanup;
  });

  it("ignores messages for other stream ids and stops listening after cleanup", async () => {
    const worker = new FakeWorker();
    const bridge = new WorkerBridge<ClientWorkerAction>(worker as unknown as Worker);
    const callback = vi.fn();
    const close = vi.fn(async () => undefined);

    const stop = bridge.handleStreamMessage("stream-1", callback, { close });

    worker.emit("message", {
      streamId: "stream-2",
      action: "stream.message",
      result: { id: "ignored" },
    });
    expect(callback).not.toHaveBeenCalled();

    worker.emit("message", {
      streamId: "stream-1",
      action: "stream.message",
      result: { id: "accepted" },
    });
    expect(callback).toHaveBeenCalledWith(null, { id: "accepted" });

    const cleanup = stop();
    await Promise.resolve();
    const endStreamRequest = worker.messages.at(-1) as
      | { action: string; id: string; data: { streamId: string } }
      | undefined;

    expect(endStreamRequest?.action).toBe("endStream");

    worker.emit("message", {
      id: endStreamRequest?.id,
      action: "endStream",
      result: undefined,
    });

    await cleanup;

    worker.emit("message", {
      streamId: "stream-1",
      action: "stream.message",
      result: { id: "late" },
    });

    expect(callback).toHaveBeenCalledTimes(1);
    expect(close).toHaveBeenCalledOnce();
  });

  it("removes the stream listener even when the close hook fails", async () => {
    const worker = new FakeWorker();
    const bridge = new WorkerBridge<ClientWorkerAction>(worker as unknown as Worker);
    const callback = vi.fn();
    const failure = new Error("close failed");
    const close = vi.fn(async () => {
      throw failure;
    });

    const stop = bridge.handleStreamMessage("stream-3", callback, { close });

    await expect(stop()).rejects.toBe(failure);

    worker.emit("message", {
      streamId: "stream-3",
      action: "stream.message",
      result: { id: "late" },
    });

    expect(callback).not.toHaveBeenCalled();
    expect(worker.messages.some((message) => {
      return (
        typeof message === "object" &&
        message !== null &&
        "action" in message &&
        (message as { action: string }).action === "endStream"
      );
    })).toBe(false);
    expect(close).toHaveBeenCalledOnce();
  });
});
