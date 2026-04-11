export class StreamFailedError extends Error {
  constructor(retryAttempts: number) {
    const times = retryAttempts === 1 ? "time" : "times";
    super(`Stream failed, retried ${retryAttempts} ${times}`);
  }
}

export class StreamInvalidRetryAttemptsError extends Error {
  constructor() {
    super("Stream retry attempts must be greater than 0");
  }
}

export class OpfsNotInitializedError extends Error {
  constructor() {
    super("OPFS must be initialized before accessing its methods");
  }
}

export class OpfsInitializationError extends Error {
  constructor() {
    super(
      "Failed to initialize OPFS, ensure that there are no other active browser-shim instances",
    );
  }
}
