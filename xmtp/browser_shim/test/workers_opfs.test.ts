import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { OpfsInitializationError, OpfsNotInitializedError } from "../src/errors";

type FileEntry = { kind: "file"; data: Uint8Array };
type FileSystemHandleLike = FileEntry | FakeDirectoryHandle;

class FakeWritable {
  #file: FileEntry;

  constructor(file: FileEntry) {
    this.#file = file;
  }

  async write(data: ArrayBufferView<ArrayBuffer>) {
    this.#file.data = new Uint8Array(
      data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength),
    );
  }

  async close() {
    return undefined;
  }
}

class FakeFileHandle {
  kind = "file" as const;
  #file: FileEntry;

  constructor(file: FileEntry) {
    this.#file = file;
  }

  async getFile() {
    const file = this.#file;
    return {
      async arrayBuffer() {
        return file.data.buffer.slice(
          file.data.byteOffset,
          file.data.byteOffset + file.data.byteLength,
        );
      },
    };
  }

  async createWritable() {
    return new FakeWritable(this.#file);
  }
}

class FakeDirectoryHandle {
  kind = "directory" as const;
  entriesMap = new Map<string, FileSystemHandleLike>();

  async *entries(): AsyncIterableIterator<[string, FileSystemHandleLike]> {
    yield* this.entriesMap.entries();
  }

  async getDirectoryHandle(name: string, options?: { create?: boolean }) {
    const existing = this.entriesMap.get(name);
    if (existing) {
      if (existing.kind !== "directory") {
        throw new Error("not a directory");
      }
      return existing;
    }

    if (!options?.create) {
      throw new Error("missing directory");
    }

    const directory = new FakeDirectoryHandle();
    this.entriesMap.set(name, directory);
    return directory;
  }

  async getFileHandle(name: string, options?: { create?: boolean }) {
    const existing = this.entriesMap.get(name);
    if (existing) {
      if (existing.kind !== "file") {
        throw new Error("not a file");
      }
      return new FakeFileHandle(existing);
    }

    if (!options?.create) {
      throw new Error("missing file");
    }

    const file: FileEntry = {
      kind: "file",
      data: new Uint8Array(),
    };
    this.entriesMap.set(name, file);
    return new FakeFileHandle(file);
  }

  async removeEntry(name: string) {
    this.entriesMap.delete(name);
  }
}

const postMessages: unknown[] = [];
let root: FakeDirectoryHandle;
let currentSelf: {
  postMessage: (message: unknown) => void;
  onmessage?: (event: MessageEvent<any>) => Promise<void> | void;
};

const installGlobals = (storageAvailable = true) => {
  root = new FakeDirectoryHandle();
  postMessages.length = 0;

  currentSelf = {
    postMessage: vi.fn((message: unknown) => {
      postMessages.push(message);
    }),
    onmessage: undefined,
  };

  vi.stubGlobal("self", currentSelf);
  vi.stubGlobal("navigator", {
    storage: storageAvailable
      ? {
          getDirectory: vi.fn(async () => root),
        }
      : undefined,
  });
};

const send = async (message: Record<string, unknown>) => {
  if (!currentSelf.onmessage) {
    throw new Error("worker not initialized");
  }

  await currentSelf.onmessage({ data: message } as MessageEvent<any>);
};

const lastMessage = () =>
  postMessages.at(-1) as
    | { id: string; action: string; result?: unknown; error?: Error }
    | undefined;

const importWorker = async () => {
  vi.resetModules();
  await import("../src/workers/opfs");
};

describe("opfs worker", () => {
  beforeEach(() => {
    installGlobals();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("initializes and performs file operations against the directory tree", async () => {
    root.entriesMap.set("alpha.db3", {
      kind: "file",
      data: new Uint8Array([1, 2, 3]),
    });
    const nested = new FakeDirectoryHandle();
    nested.entriesMap.set("beta.db3", {
      kind: "file",
      data: new Uint8Array([4, 5, 6]),
    });
    root.entriesMap.set("nested", nested);

    await importWorker();

    await send({
      action: "opfs.init",
      id: "1",
      data: { enableLogging: true },
    });
    expect(lastMessage()).toEqual({
      id: "1",
      action: "opfs.init",
      result: undefined,
    });

    await send({ action: "opfs.listFiles", id: "2", data: undefined });
    expect(lastMessage()?.result).toEqual(["alpha.db3", "nested/beta.db3"]);

    await send({ action: "opfs.fileCount", id: "3", data: undefined });
    expect(lastMessage()?.result).toBe(2);

    await send({
      action: "opfs.fileExists",
      id: "4",
      data: { path: "nested/beta.db3" },
    });
    expect(lastMessage()?.result).toBe(true);

    await send({
      action: "opfs.deleteFile",
      id: "5",
      data: { path: "nested/beta.db3" },
    });
    expect(lastMessage()).toEqual({
      id: "5",
      action: "opfs.deleteFile",
      result: true,
    });

    await send({ action: "opfs.fileCount", id: "6", data: undefined });
    expect(lastMessage()?.result).toBe(1);

    await send({
      action: "opfs.exportDb",
      id: "7",
      data: { path: "alpha.db3" },
    });
    expect(lastMessage()?.result).toEqual(new Uint8Array([1, 2, 3]));

    await send({
      action: "opfs.importDb",
      id: "8",
      data: { path: "imported.db3", data: new Uint8Array([7, 8, 9]) },
    });
    expect(lastMessage()).toEqual({
      id: "8",
      action: "opfs.importDb",
      result: undefined,
    });

    await send({ action: "opfs.listFiles", id: "9", data: undefined });
    expect(lastMessage()?.result).toEqual(["alpha.db3", "imported.db3"]);

    await send({ action: "opfs.clearAll", id: "10", data: undefined });
    expect(lastMessage()).toEqual({
      id: "10",
      action: "opfs.clearAll",
      result: undefined,
    });

    await send({ action: "opfs.fileCount", id: "11", data: undefined });
    expect(lastMessage()?.result).toBe(0);
  });

  it("returns not-initialized and initialization errors", async () => {
    await importWorker();

    await send({
      action: "opfs.listFiles",
      id: "1",
      data: undefined,
    });
    expect(lastMessage()?.error).toHaveProperty(
      "message",
      new OpfsNotInitializedError().message,
    );

    vi.unstubAllGlobals();
    installGlobals(false);
    await importWorker();

    await send({
      action: "opfs.init",
      id: "2",
      data: { enableLogging: false },
    });
    expect(lastMessage()?.error).toHaveProperty(
      "message",
      new OpfsInitializationError().message,
    );
  });

  it("propagates export failures and ignores missing file deletions", async () => {
    root.entriesMap.set("alpha.db3", {
      kind: "file",
      data: new Uint8Array([1, 2, 3]),
    });

    await importWorker();
    await send({
      action: "opfs.init",
      id: "1",
      data: { enableLogging: false },
    });

    await send({
      action: "opfs.exportDb",
      id: "2",
      data: { path: "missing.db3" },
    });
    expect(lastMessage()?.error).toHaveProperty(
      "message",
      new Error("missing file").message,
    );

    await send({
      action: "opfs.deleteFile",
      id: "3",
      data: { path: "missing.db3" },
    });
    expect(lastMessage()).toEqual({
      id: "3",
      action: "opfs.deleteFile",
      result: false,
    });
  });

  it("overwrites an existing file when importing again", async () => {
    root.entriesMap.set("alpha.db3", {
      kind: "file",
      data: new Uint8Array([1, 2, 3]),
    });

    await importWorker();
    await send({
      action: "opfs.init",
      id: "1",
      data: { enableLogging: false },
    });

    await send({
      action: "opfs.importDb",
      id: "2",
      data: { path: "alpha.db3", data: new Uint8Array([9, 8, 7]) },
    });
    expect(lastMessage()).toEqual({
      id: "2",
      action: "opfs.importDb",
      result: undefined,
    });

    await send({
      action: "opfs.exportDb",
      id: "3",
      data: { path: "alpha.db3" },
    });
    expect(lastMessage()?.result).toEqual(new Uint8Array([9, 8, 7]));
  });
});
