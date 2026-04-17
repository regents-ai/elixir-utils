import { AsyncStream, createAsyncStreamProxy } from "./AsyncStream";
import { StreamFailedError, StreamInvalidRetryAttemptsError } from "./errors";

const isPromise = <T = unknown>(value: unknown): value is Promise<T> => {
  return (
    !!value &&
    (typeof value === "object" || typeof value === "function") &&
    "then" in value &&
    typeof (value as { then?: unknown }).then === "function"
  );
};

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export const DEFAULT_RETRY_DELAY = 10_000;
export const DEFAULT_RETRY_ATTEMPTS = 6;

export type StreamOptions<T = unknown, V = T> = {
  onEnd?: () => void;
  onError?: (error: Error) => void;
  onFail?: () => void;
  onRestart?: () => void;
  onRetry?: (attempts: number, maxAttempts: number) => void;
  onValue?: (value: V) => void;
  retryAttempts?: number;
  retryDelay?: number;
  retryOnFail?: boolean;
  disableSync?: boolean;
};

export type StreamCallback<T = unknown> = (
  error: Error | null,
  value: T | undefined,
) => void;

export type StreamFunction<T = unknown> = (
  callback: StreamCallback<T>,
  onFail: () => void,
) => Promise<() => void>;

export type StreamValueMutator<T = unknown, V = T> = (value: T) => V | Promise<V>;

export const createStream = async <T = unknown, V = T>(
  streamFunction: StreamFunction<T>,
  streamValueMutator?: StreamValueMutator<T, V | undefined>,
  options?: StreamOptions<T, V>,
) => {
  const {
    onEnd,
    onError,
    onFail,
    onRestart,
    onRetry,
    onValue,
    retryAttempts = DEFAULT_RETRY_ATTEMPTS,
    retryDelay = DEFAULT_RETRY_DELAY,
    retryOnFail = true,
  } = options ?? {};

  if (retryOnFail && retryAttempts < 0) {
    throw new StreamInvalidRetryAttemptsError();
  }

  const asyncStream = new AsyncStream<V>();
  const streamCallback: StreamCallback<T> = (error, value) => {
    if (error) {
      onError?.(error);
      return;
    }

    if (value === undefined) {
      return;
    }

    try {
      if (streamValueMutator) {
        const mutatedValue = streamValueMutator(value);
        if (isPromise(mutatedValue)) {
          void mutatedValue
            .then((next) => {
              if (next !== undefined) {
                asyncStream.push(next);
                onValue?.(next);
              }
            })
            .catch((mutatorError: unknown) => {
              onError?.(mutatorError as Error);
            });
        } else if (mutatedValue !== undefined) {
          asyncStream.push(mutatedValue);
          onValue?.(mutatedValue);
        }
        return;
      }

      asyncStream.push(value as unknown as V);
      onValue?.(value as unknown as V);
    } catch (streamError) {
      onError?.(streamError as Error);
    }
  };

  const retry = async (retries: number = retryAttempts) => {
    try {
      if (retries === 0) {
        void asyncStream.end();
        throw new StreamFailedError(retryAttempts);
      }

      await wait(retryDelay);
      onRetry?.(retryAttempts - retries + 1, retryAttempts);

      const streamCloser = await streamFunction(streamCallback, () => {
        onFail?.();
        void retry();
      });

      asyncStream.onDone = () => {
        streamCloser();
        onEnd?.();
      };

      onRestart?.();
    } catch (error) {
      onError?.(error as Error);
      if (retries > 0) {
        void retry(retries - 1);
      }
    }
  };

  const startRetry = () => {
    if (retryOnFail) {
      void retry();
      return;
    }

    void asyncStream.end();
    throw new StreamFailedError(0);
  };

  try {
    const streamCloser = await streamFunction(streamCallback, () => {
      onFail?.();
      startRetry();
    });

    asyncStream.onDone = () => {
      streamCloser();
      onEnd?.();
    };
  } catch (error) {
    onError?.(error as Error);
    startRetry();
  }

  return createAsyncStreamProxy(asyncStream);
};
