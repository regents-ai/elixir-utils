import { describe, expect, it, vi } from "vitest";
import { AsyncStream, createAsyncStreamProxy } from "../src/AsyncStream";

describe("AsyncStream", () => {
  it("returns pushed values in sequence", async () => {
    const stream = new AsyncStream<number>();
    const onReturn = vi.fn();
    const onDone = vi.fn();

    stream.onReturn = onReturn;
    stream.onDone = onDone;

    stream.push(1);
    stream.push(2);
    stream.push(3);

    const values: number[] = [];
    let count = 0;

    for await (const value of stream) {
      values.push(value as number);
      count += 1;
      if (count === 3) {
        break;
      }
    }

    expect(values).toEqual([1, 2, 3]);
    expect(onReturn).toHaveBeenCalledOnce();
    expect(onDone).toHaveBeenCalledOnce();
    expect(stream.isDone).toBe(true);
  });

  it("handles values added during iteration", async () => {
    const stream = new AsyncStream<number>();
    const onReturn = vi.fn();
    const onDone = vi.fn();

    stream.onReturn = onReturn;
    stream.onDone = onDone;

    stream.push(1);

    const values: number[] = [];
    let count = 0;

    for await (const value of stream) {
      values.push(value as number);
      count += 1;

      if (count === 1) {
        stream.push(2);
        stream.push(3);
      }

      if (count === 3) {
        break;
      }
    }

    expect(values).toEqual([1, 2, 3]);
    expect(onReturn).toHaveBeenCalledOnce();
    expect(onDone).toHaveBeenCalledOnce();
    expect(stream.isDone).toBe(true);
  });

  it("cleans up when iteration throws", async () => {
    const stream = new AsyncStream<number>();
    const onReturn = vi.fn();
    const onDone = vi.fn();
    const testError = new Error("test");

    stream.onReturn = onReturn;
    stream.onDone = onDone;
    stream.push(1);
    stream.push(2);

    try {
      for await (const value of stream) {
        expect(value).toBe(1);
        throw testError;
      }
    } catch (error) {
      expect(error).toBe(testError);
    }

    expect(onReturn).toHaveBeenCalledOnce();
    expect(onDone).toHaveBeenCalledOnce();
    expect(stream.isDone).toBe(true);
  });

  it("finishes pending consumers when done is called", async () => {
    const stream = new AsyncStream<number>();
    const onDone = vi.fn();

    stream.onDone = onDone;
    const pending = stream.next();
    stream.done();

    expect(await pending).toEqual({ done: true, value: undefined });
    expect(await stream.next()).toEqual({ done: true, value: undefined });
    expect(onDone).toHaveBeenCalledOnce();
    expect(stream.isDone).toBe(true);
  });

  it("returns pending consumers on return", async () => {
    const stream = new AsyncStream<number>();
    const onReturn = vi.fn();
    stream.onReturn = onReturn;

    const next1 = stream.next();
    const next2 = stream.next();
    const result = await stream.return();

    expect(result).toEqual({ done: true, value: undefined });
    expect(await next1).toEqual({ done: true, value: undefined });
    expect(await next2).toEqual({ done: true, value: undefined });
    expect(onReturn).toHaveBeenCalledOnce();
  });

  it("handles concurrent next calls", async () => {
    const stream = new AsyncStream<number>();

    const next1 = stream.next();
    const next2 = stream.next();
    const next3 = stream.next();

    stream.push(1);
    stream.push(2);
    stream.push(3);

    const [result1, result2, result3] = await Promise.all([
      next1,
      next2,
      next3,
    ]);

    expect(result1).toEqual({ done: false, value: 1 });
    expect(result2).toEqual({ done: false, value: 2 });
    expect(result3).toEqual({ done: false, value: 3 });
    expect(stream.isDone).toBe(false);
  });

  it("keeps queue values when consumers are slower than producers", async () => {
    const stream = new AsyncStream<number>();

    for (let i = 1; i <= 5; i += 1) {
      stream.push(i);
    }

    const values: number[] = [];
    for (let i = 0; i < 3; i += 1) {
      const result = await stream.next();
      expect(result.done).toBe(false);
      values.push(result.value as number);
    }

    expect(values).toEqual([1, 2, 3]);
    expect(stream.isDone).toBe(false);

    await stream.end();
    expect(await stream.next()).toEqual({ done: true, value: undefined });
  });
});

describe("createAsyncStreamProxy", () => {
  it("only exposes allowed methods and properties", () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    expect(typeof proxy.next).toBe("function");
    expect(typeof proxy.end).toBe("function");
    expect(typeof proxy.return).toBe("function");
    expect(typeof proxy[Symbol.asyncIterator]).toBe("function");

    const ownProperties = Object.getOwnPropertyNames(proxy);
    expect(ownProperties).toHaveLength(4);
    expect(ownProperties).toContain("end");
    expect(ownProperties).toContain("return");
    expect(ownProperties).toContain("isDone");
    expect(ownProperties).toContain("next");
  });

  it("prevents setting properties", () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    proxy.isDone = true;

    expect(proxy.isDone).toBe(false);
  });

  it("forwards next and end to the underlying stream", async () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);
    const onDone = vi.fn();
    stream.onDone = onDone;

    stream.push(1);
    expect(await proxy.next()).toEqual({ done: false, value: 1 });
    expect(await proxy.end()).toEqual({ done: true, value: undefined });
    expect(onDone).toHaveBeenCalledOnce();
    expect(proxy.isDone).toBe(true);
  });

  it("maintains async iterator functionality", async () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    stream.push(1);
    stream.push(2);
    stream.push(3);

    const values: number[] = [];
    let count = 0;
    for await (const value of proxy) {
      values.push(value);
      count += 1;
      if (count === 3) {
        break;
      }
    }

    expect(values).toEqual([1, 2, 3]);
    expect(stream.isDone).toBe(true);
    expect(proxy.isDone).toBe(true);
  });

  it("ends iteration when the proxy is ended", async () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);
    const onDone = vi.fn();
    stream.onDone = onDone;

    stream.push(1);
    stream.push(2);

    setTimeout(() => {
      void proxy.end();
    }, 0);

    const values: number[] = [];
    for await (const value of proxy) {
      values.push(value);
    }

    expect(values).toEqual([1, 2]);
    expect(onDone).toHaveBeenCalledOnce();
    expect(stream.isDone).toBe(true);
  });

  it("implements has, ownKeys, and descriptors", () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    expect("isDone" in proxy).toBe(true);
    expect("next" in proxy).toBe(true);
    expect("end" in proxy).toBe(true);
    expect("return" in proxy).toBe(true);
    expect(Symbol.asyncIterator in proxy).toBe(true);
    expect("push" in proxy).toBe(false);
    expect("onDone" in proxy).toBe(false);

    const keys = Object.getOwnPropertyNames(proxy);
    const symbols = Object.getOwnPropertySymbols(proxy);
    expect(keys).toHaveLength(4);
    expect(keys).toContain("next");
    expect(keys).toContain("end");
    expect(keys).toContain("return");
    expect(keys).toContain("isDone");
    expect(symbols).toHaveLength(1);
    expect(symbols).toContain(Symbol.asyncIterator);

    const nextDescriptor = Object.getOwnPropertyDescriptor(proxy, "next");
    expect(nextDescriptor).toMatchObject({
      enumerable: true,
      configurable: true,
    });
    expect(typeof nextDescriptor?.value).toBe("function");

    const isDoneDescriptor = Object.getOwnPropertyDescriptor(proxy, "isDone");
    expect(isDoneDescriptor).toMatchObject({
      enumerable: true,
      configurable: true,
    });
  });

  it("handles concurrent operations through proxy", async () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    const next1 = proxy.next();
    const next2 = proxy.next();
    const next3 = proxy.next();

    stream.push(1);
    stream.push(2);
    stream.push(3);

    const [result1, result2, result3] = await Promise.all([
      next1,
      next2,
      next3,
    ]);

    expect(result1).toEqual({ done: false, value: 1 });
    expect(result2).toEqual({ done: false, value: 2 });
    expect(result3).toEqual({ done: false, value: 3 });
  });

  it("works when the stream is already done", async () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    stream.push(1);
    await proxy.end();

    expect(await proxy.next()).toEqual({ done: true, value: undefined });
    expect(await proxy.next()).toEqual({ done: true, value: undefined });
  });

  it("ignores pushes after done is called", async () => {
    const stream = new AsyncStream<number>();
    stream.push(1);
    await stream.done();

    stream.push(2);
    expect(await stream.next()).toEqual({ done: true, value: undefined });
  });

  it("flushes pending consumers in FIFO order", async () => {
    const stream = new AsyncStream<number>();
    const next1 = stream.next();
    const next2 = stream.next();

    stream.flush();

    await expect(next1).resolves.toEqual({ done: true, value: undefined });
    await expect(next2).resolves.toEqual({ done: true, value: undefined });
  });

  it("exposes descriptors for return and async iterator", () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    expect(Object.getOwnPropertyDescriptor(proxy, "return")).toMatchObject({
      enumerable: true,
      configurable: true,
    });
    expect(
      Object.getOwnPropertyDescriptor(proxy, Symbol.asyncIterator),
    ).toMatchObject({
      enumerable: true,
      configurable: true,
    });
  });

  it("does not report unsupported properties", () => {
    const stream = new AsyncStream<number>();
    const proxy = createAsyncStreamProxy(stream);

    expect("push" in proxy).toBe(false);
    expect("done" in proxy).toBe(false);
    expect(Object.getOwnPropertyDescriptor(proxy, "push")).toBeUndefined();
  });
});
