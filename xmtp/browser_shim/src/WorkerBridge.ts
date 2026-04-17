import type {
  ActionErrorData,
  ActionName,
  ActionWithoutData,
  ExtractActionData,
  ExtractActionResult,
  StreamAction,
  StreamActionErrorData,
  UnknownAction,
} from "./contracts";
import type { StreamOptions } from "./streams";
import { uuid } from "./uuid";

const handleError = (event: ErrorEvent) => {
  console.error(`[worker] error: ${event.message}`);
};

export class WorkerBridge<T extends UnknownAction> {
  #worker: Worker;
  #enableLogging: boolean;
  #promises = new Map<
    string,
    {
      resolve: (value: unknown) => void;
      reject: (reason?: unknown) => void;
    }
  >();

  constructor(worker: Worker, enableLogging?: boolean) {
    this.#worker = worker;
    this.#worker.addEventListener("message", this.handleMessage);
    this.#worker.addEventListener("error", handleError);
    this.#enableLogging = enableLogging ?? false;
  }

  action<
    A extends ActionName<T>,
    D = ExtractActionData<T, A>,
    R = ExtractActionResult<T, A>,
  >(action: A, ...args: D extends undefined ? [] : [data: D]) {
    const promiseId = uuid();
    this.#worker.postMessage({
      action,
      id: promiseId,
      data: args[0],
    });
    const promise = new Promise((resolve, reject) => {
      this.#promises.set(promiseId, {
        resolve: resolve as (value: unknown) => void,
        reject,
      });
    });
    return promise as [R] extends [undefined] ? Promise<void> : Promise<R>;
  }

  handleMessage = (event: MessageEvent<ActionWithoutData<T> | ActionErrorData<T>>) => {
    const eventData = event.data;
    if (this.#enableLogging) {
      console.log("[worker] client received event data", eventData);
    }

    const promise = this.#promises.get(eventData.id);
    if (!promise) {
      return;
    }

    this.#promises.delete(eventData.id);
    if ("error" in eventData) {
      promise.reject(eventData.error);
      return;
    }

    promise.resolve(eventData.result);
  };

  endStream = (streamId: string) => {
    const action = this.action.bind(this) as unknown as (
      action: "endStream",
      data: { streamId: string },
    ) => Promise<void>;
    return action("endStream", { streamId });
  };

  handleStreamMessage = <R, V = R>(
    streamId: string,
    callback: (error: Error | null, value: R | undefined) => void,
    options?: StreamOptions<R, V> & {
      close?: () => void | Promise<void>;
    },
  ) => {
    const streamHandler = (event: MessageEvent<StreamAction | StreamActionErrorData>) => {
      const eventData = event.data;
      if (eventData.streamId !== streamId) {
        return;
      }

      if (eventData.action === "stream.fail") {
        options?.onFail?.();
        return;
      }

      if ("error" in eventData && eventData.error) {
        callback(eventData.error, undefined);
        return;
      }

      if ("result" in eventData) {
        callback(null, eventData.result as R);
      }
    };

    this.#worker.addEventListener("message", streamHandler);

    return async () => {
      try {
        await options?.close?.();
        await this.endStream(streamId);
      } finally {
        this.#worker.removeEventListener("message", streamHandler);
      }
    };
  };

  close() {
    this.#worker.removeEventListener("message", this.handleMessage);
    this.#worker.removeEventListener("error", handleError);
    this.#worker.terminate();
  }
}
