import { describe, expect, it, vi } from "vitest";
import {
  StreamFailedError,
  StreamInvalidRetryAttemptsError,
} from "../src/errors";
import {
  createStream,
  DEFAULT_RETRY_ATTEMPTS,
  DEFAULT_RETRY_DELAY,
  type StreamCallback,
  type StreamFunction,
} from "../src/streams";

describe("createStream", () => {
  it("creates a stream and emits values", async () => {
    const onValue = vi.fn();

    const stream = await createStream<number>(
      vi.fn(async (callback: StreamCallback<number>) => {
        callback(null, 1);
        callback(null, undefined);
        callback(null, 2);
        return Promise.resolve(() => {});
      }),
      undefined,
      { onValue },
    );

    const values: number[] = [];
    for await (const value of stream) {
      values.push(value);
      if (values.length === 2) {
        break;
      }
    }

    expect(values).toEqual([1, 2]);
    expect(onValue).toHaveBeenCalledTimes(2);
  });

  it("applies sync and async value mutators", async () => {
    const syncStream = await createStream<number, number>(
      vi.fn(async (callback: StreamCallback<number>) => {
        callback(null, 5);
        return Promise.resolve(() => {});
      }),
      (value) => value * 2,
    );

    const asyncStream = await createStream<number, number>(
      vi.fn(async (callback: StreamCallback<number>) => {
        callback(null, 7);
        return Promise.resolve(() => {});
      }),
      async (value) => value * 3,
    );

    const syncValues: number[] = [];
    const asyncValues: number[] = [];

    for await (const value of syncStream) {
      syncValues.push(value);
      break;
    }

    for await (const value of asyncStream) {
      asyncValues.push(value);
      break;
    }

    expect(syncValues).toEqual([10]);
    expect(asyncValues).toEqual([21]);
  });

  it("calls onError when a mutator throws or rejects", async () => {
    const syncError = new Error("sync mutator");
    const asyncError = new Error("async mutator");
    const onError = vi.fn();

    const syncStream = await createStream<number>(
      vi.fn(async (callback) => {
        callback(null, 5);
        return Promise.resolve(() => {});
      }),
      () => {
        throw syncError;
      },
      { onError },
    );

    const asyncStream = await createStream<number>(
      vi.fn(async (callback) => {
        callback(null, 7);
        return Promise.resolve(() => {});
      }),
      async () => {
        throw asyncError;
      },
      { onError },
    );

    await syncStream.end();
    await asyncStream.end();

    expect(onError).toHaveBeenCalledWith(syncError);
    expect(onError).toHaveBeenCalledWith(asyncError);
  });

  it("calls onEnd and stream closer when the stream ends", async () => {
    const onEnd = vi.fn();
    const streamCloser = vi.fn();

    const stream = await createStream<number>(
      vi.fn(async (callback) => {
        callback(null, 1);
        return Promise.resolve(streamCloser);
      }),
      undefined,
      { onEnd },
    );

    await stream.end();

    expect(onEnd).toHaveBeenCalledOnce();
    expect(streamCloser).toHaveBeenCalledOnce();
  });

  it("rejects invalid retry attempts when retrying is enabled", async () => {
    await expect(
      createStream(
        vi.fn(async () => Promise.resolve(() => {})),
        undefined,
        { retryAttempts: -1, retryOnFail: true },
      ),
    ).rejects.toBeInstanceOf(StreamInvalidRetryAttemptsError);
  });

  it("allows negative retry attempts when retrying is disabled", async () => {
    const stream = await createStream(
      vi.fn(async () => Promise.resolve(() => {})),
      undefined,
      { retryAttempts: -1, retryOnFail: false },
    );

    await stream.end();
  });

  it("calls onFail and throws when retrying is disabled", async () => {
    const onFail = vi.fn();

    await expect(
      createStream(
        vi.fn(async (_callback, fail) => {
          fail();
          return Promise.resolve(() => {});
        }),
        undefined,
        { retryOnFail: false, onFail },
      ),
    ).rejects.toBeInstanceOf(StreamFailedError);

    expect(onFail).toHaveBeenCalledOnce();
  });

  it("retries after an initial failure and restarts successfully", async () => {
    vi.useFakeTimers();

    const onError = vi.fn();
    const onFail = vi.fn();
    const onRetry = vi.fn();
    const onRestart = vi.fn();
    const onEnd = vi.fn();
    let callCount = 0;

    const stream = await createStream<number>(
      vi.fn(async (callback) => {
        callCount += 1;
        if (callCount === 1) {
          throw new Error("initial failure");
        }

        callback(null, 42);
        return Promise.resolve(() => {});
      }),
      undefined,
      {
        onError,
        onFail,
        onRetry,
        onRestart,
        onEnd,
        retryAttempts: 2,
        retryDelay: 25,
      },
    );

    const values: number[] = [];
    const reader = (async () => {
      for await (const value of stream) {
        values.push(value);
        if (values.length === 1) {
          break;
        }
      }
    })();

    await vi.advanceTimersByTimeAsync(25);
    await reader;
    await stream.end();
    vi.useRealTimers();

    expect(onError).toHaveBeenCalledWith(new Error("initial failure"));
    expect(onRetry).toHaveBeenCalledWith(1, 2);
    expect(onRestart).toHaveBeenCalledOnce();
    expect(onFail).not.toHaveBeenCalled();
    expect(onEnd).toHaveBeenCalledOnce();
    expect(values).toEqual([42]);
  });

  it("retries when the stream signals failure and preserves attempt counts", async () => {
    vi.useFakeTimers();

    const onFail = vi.fn();
    const onRetry = vi.fn();
    const onRestart = vi.fn();
    let attempts = 0;

    const stream = await createStream<number>(
      vi.fn(async (callback, fail) => {
        attempts += 1;
        if (attempts === 1) {
          fail();
        } else {
          callback(null, 42);
        }
        return Promise.resolve(() => {});
      }),
      undefined,
      {
        onFail,
        onRetry,
        onRestart,
        retryAttempts: 1,
        retryDelay: 10,
      },
    );

    const next = stream.next();
    await vi.advanceTimersByTimeAsync(10);
    const result = await next;
    await stream.end();
    vi.useRealTimers();

    expect(result).toEqual({ done: false, value: 42 });
    expect(onFail).toHaveBeenCalledOnce();
    expect(onRetry).toHaveBeenCalledWith(1, 1);
    expect(onRestart).toHaveBeenCalledOnce();
  });

  it("calls retry callbacks in the expected order", async () => {
    vi.useFakeTimers();

    const events: string[] = [];
    let callCount = 0;

    const stream = await createStream<number>(
      vi.fn(async (_callback, fail) => {
        callCount += 1;
        events.push(`start:${callCount}`);
        if (callCount === 1) {
          events.push("fail");
          fail();
        } else {
          events.push("restart");
        }
        return Promise.resolve(() => {
          events.push(`close:${callCount}`);
        });
      }),
      undefined,
      {
        retryAttempts: 1,
        retryDelay: 5,
        onFail: () => events.push("onFail"),
        onRetry: (attempt, max) => events.push(`onRetry:${attempt}/${max}`),
        onRestart: () => events.push("onRestart"),
        onEnd: () => events.push("onEnd"),
      },
    );

    await vi.advanceTimersByTimeAsync(5);
    await stream.end();
    vi.useRealTimers();

    expect(events).toEqual([
      "start:1",
      "fail",
      "onFail",
      "onRetry:1/1",
      "start:2",
      "restart",
      "onRestart",
      "close:2",
      "onEnd",
    ]);
  });

  it("fails after exhausting retries with the correct message", async () => {
    vi.useFakeTimers();

    const onError = vi.fn();
    const onRetry = vi.fn();

    const stream = await createStream<number>(
      vi.fn(async () => {
        throw new Error("always fails");
      }),
      undefined,
      {
        onError,
        onRetry,
        retryAttempts: 2,
        retryDelay: 10,
      },
    );

    await vi.advanceTimersByTimeAsync(30);
    await expect(stream.end()).resolves.toEqual({ done: true, value: undefined });
    vi.useRealTimers();

    const streamFailedError = onError.mock.calls
      .map(([error]) => error)
      .find((error) => error instanceof StreamFailedError);

    expect(onRetry).toHaveBeenCalledWith(1, 2);
    expect(onRetry).toHaveBeenCalledWith(2, 2);
    expect(streamFailedError).toBeInstanceOf(StreamFailedError);
    expect((streamFailedError as Error).message).toBe(
      "Stream failed, retried 2 times",
    );
  });

  it("calls onError for each failed retry attempt", async () => {
    vi.useFakeTimers();

    const onError = vi.fn();
    const onRetry = vi.fn();

    const stream = await createStream<number>(
      vi.fn(async () => {
        throw new Error("always fails");
      }),
      undefined,
      {
        onError,
        onRetry,
        retryAttempts: 2,
        retryDelay: 5,
      },
    );

    await vi.advanceTimersByTimeAsync(20);
    await stream.end();
    vi.useRealTimers();

    expect(onRetry).toHaveBeenCalledTimes(2);
    expect(onError.mock.calls.length).toBeGreaterThan(1);
    expect(
      onError.mock.calls.some(
        ([error]) => error instanceof StreamFailedError,
      ),
    ).toBe(true);
  });

  it("handles retry during retry", async () => {
    vi.useFakeTimers();

    const onFail = vi.fn();
    const onRetry = vi.fn();
    const onError = vi.fn();
    const events: string[] = [];
    let attempts = 0;

    const stream = await createStream<number>(
      vi.fn(async (_callback, fail) => {
        attempts += 1;
        events.push(`start:${attempts}`);
        if (attempts === 1) {
          events.push("fail:1");
          fail();
        } else if (attempts === 2) {
          events.push("fail:2");
          fail();
        } else {
          events.push("recover");
        }
        return Promise.resolve(() => {
          events.push(`close:${attempts}`);
        });
      }),
      undefined,
      {
        onFail,
        onRetry,
        onError,
        retryAttempts: 2,
        retryDelay: 5,
      },
    );

    await vi.advanceTimersByTimeAsync(15);
    await stream.end();
    vi.useRealTimers();

    expect(onFail).toHaveBeenCalledTimes(2);
    expect(onRetry).toHaveBeenCalledTimes(2);
    expect(onRetry.mock.calls[0]).toEqual([1, 2]);
    expect(onRetry.mock.calls[1]).toEqual([1, 2]);
    expect(onError).not.toHaveBeenCalledWith(expect.any(Error));
    expect(events).toEqual([
      "start:1",
      "fail:1",
      "start:2",
      "fail:2",
      "start:3",
      "recover",
      "close:3",
    ]);
  });

  it("handles retryAttempts of zero without retrying", async () => {
    vi.useFakeTimers();

    const onError = vi.fn();

    const stream = await createStream<number>(
      vi.fn(async () => {
        throw new Error("initial failure");
      }),
      undefined,
      {
        onError,
        retryAttempts: 0,
        retryDelay: 10,
      },
    );

    await vi.advanceTimersByTimeAsync(10);
    await stream.end();
    vi.useRealTimers();

    const streamFailedErrors = onError.mock.calls
      .map(([error]) => error)
      .filter((error) => error instanceof StreamFailedError);

    expect(streamFailedErrors).toHaveLength(1);
    expect((streamFailedErrors[0] as Error).message).toBe(
      "Stream failed, retried 0 times",
    );
  });

  it("uses the documented default retry values", () => {
    expect(DEFAULT_RETRY_ATTEMPTS).toBe(6);
    expect(DEFAULT_RETRY_DELAY).toBe(10_000);
  });

  it("works with default options", async () => {
    const stream = await createStream<number>(
      vi.fn(async (callback) => {
        callback(null, 1);
        callback(null, 2);
        return Promise.resolve(() => {});
      }),
    );

    const values: number[] = [];
    for await (const value of stream) {
      values.push(value);
      if (values.length === 2) {
        break;
      }
    }

    expect(values).toEqual([1, 2]);
  });

  it("calls onValue when no mutator is provided", async () => {
    const onValue = vi.fn();
    const stream = await createStream<number>(
      vi.fn(async (callback) => {
        callback(null, 9);
        return Promise.resolve(() => {});
      }),
      undefined,
      { onValue },
    );

    await stream.end();
    expect(onValue).toHaveBeenCalledWith(9);
  });

  it("uses the custom retry delay before retrying", async () => {
    vi.useFakeTimers();

    const onRetry = vi.fn();
    let callCount = 0;

    const stream = await createStream<number>(
      vi.fn(async () => {
        callCount += 1;
        if (callCount === 1) {
          throw new Error("first failure");
        }
        return Promise.resolve(() => {});
      }),
      undefined,
      { onRetry, retryAttempts: 1, retryDelay: 25 },
    );

    await vi.advanceTimersByTimeAsync(24);
    expect(onRetry).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1);
    expect(onRetry).toHaveBeenCalledWith(1, 1);
    await stream.end();
    vi.useRealTimers();
  });

  it("reports singular retry messaging when retryAttempts is 1", async () => {
    vi.useFakeTimers();

    const onError = vi.fn();
    const stream = await createStream<number>(
      vi.fn(async () => {
        throw new Error("always fails");
      }),
      undefined,
      { onError, retryAttempts: 1, retryDelay: 5 },
    );

    await vi.advanceTimersByTimeAsync(10);
    await stream.end();
    vi.useRealTimers();

    const streamFailedError = onError.mock.calls
      .map(([error]) => error)
      .find((error) => error instanceof StreamFailedError);

    expect((streamFailedError as Error).message).toBe(
      "Stream failed, retried 1 time",
    );
  });

  it("fails immediately when retrying is disabled during initial startup failure", async () => {
    const onError = vi.fn();

    await expect(
      createStream(
        vi.fn(async () => {
          throw new Error("startup failed");
        }),
        undefined,
        { retryOnFail: false, onError },
      ),
    ).rejects.toBeInstanceOf(StreamFailedError);

    expect(onError).toHaveBeenCalledWith(expect.any(Error));
  });

  it("calls onEnd and streamCloser after a successful retry", async () => {
    vi.useFakeTimers();

    const onEnd = vi.fn();
    const events: string[] = [];
    let attempt = 0;

    const stream = await createStream<number>(
      vi.fn(async (callback) => {
        attempt += 1;
        if (attempt === 1) {
          throw new Error("first failure");
        }
        callback(null, 7);
        return Promise.resolve(() => {
          events.push("close");
        });
      }),
      undefined,
      {
        onEnd,
        retryAttempts: 1,
        retryDelay: 5,
      },
    );

    const values: number[] = [];
    const reader = (async () => {
      for await (const value of stream) {
        values.push(value);
        break;
      }
    })();

    await vi.advanceTimersByTimeAsync(5);
    await reader;
    await stream.end();
    vi.useRealTimers();

    expect(values).toEqual([7]);
    expect(events).toEqual(["close"]);
    expect(onEnd).toHaveBeenCalledOnce();
  });

  it("handles no options provided", async () => {
    const stream = await createStream<number>(
      vi.fn(async (callback) => {
        callback(null, 3);
        return Promise.resolve(() => {});
      }),
    );

    const result = await stream.next();
    expect(result).toEqual({ done: false, value: 3 });
    await stream.end();
  });
});
