import type { ActionErrorData, ActionWithoutData, OpfsAction } from "../contracts";
import { OpfsInitializationError, OpfsNotInitializedError } from "../errors";

let initialized = false;
let enableLogging = false;
let root: FileSystemDirectoryHandle | undefined;

type DirectoryHandleWithEntries = FileSystemDirectoryHandle & {
  entries(): AsyncIterableIterator<[string, FileSystemHandle]>;
};

const log = (...args: unknown[]) => {
  if (enableLogging) {
    console.log("[worker] opfs", ...args);
  }
};

const postMessage = <A extends OpfsAction["action"]>(
  data: ActionWithoutData<OpfsAction> | ActionErrorData<OpfsAction>,
) => {
  self.postMessage(data);
};

const getRoot = async () => {
  const storage = (globalThis.navigator as Navigator | undefined)?.storage;
  if (!storage?.getDirectory) {
    throw new OpfsInitializationError();
  }
  return storage.getDirectory();
};

const walk = async (directory: FileSystemDirectoryHandle, prefix = ""): Promise<string[]> => {
  const files: string[] = [];
  // eslint-disable-next-line no-restricted-syntax
  for await (const [name, handle] of (directory as DirectoryHandleWithEntries).entries()) {
    const path = prefix ? `${prefix}/${name}` : name;
    if (handle.kind === "file") {
      files.push(path);
      continue;
    }
    files.push(...(await walk(handle as FileSystemDirectoryHandle, path)));
  }
  return files;
};

const getPathParts = (path: string) => path.split("/").filter(Boolean);

const getParentDirectory = async (path: string, create = false) => {
  if (!root) {
    throw new OpfsNotInitializedError();
  }

  const parts = getPathParts(path);
  const fileName = parts.pop();
  if (!fileName) {
    throw new Error("path is required");
  }

  let dir = root;
  for (const part of parts) {
    dir = await dir.getDirectoryHandle(part, { create });
  }

  return { dir, fileName };
};

const fileExists = async (path: string) => {
  try {
    const { dir, fileName } = await getParentDirectory(path);
    await dir.getFileHandle(fileName);
    return true;
  } catch {
    return false;
  }
};

const readFile = async (path: string) => {
  const { dir, fileName } = await getParentDirectory(path);
  const handle = await dir.getFileHandle(fileName);
  const file = await handle.getFile();
  return new Uint8Array(await file.arrayBuffer());
};

const writeFile = async (path: string, data: Uint8Array) => {
  const { dir, fileName } = await getParentDirectory(path, true);
  const handle = await dir.getFileHandle(fileName, { create: true });
  const writable = await handle.createWritable();
  await writable.write(data as unknown as ArrayBufferView<ArrayBuffer>);
  await writable.close();
};

self.onmessage = async (event: MessageEvent<OpfsAction>) => {
  const { action, id, data } = event.data;

  try {
    if (action === "opfs.init") {
      if (!initialized) {
        root = await getRoot();
        initialized = true;
        enableLogging = data.enableLogging ?? false;
      }
      postMessage({ id, action, result: undefined });
      return;
    }

    if (enableLogging) {
      log("received", event.data);
    }

    if (!initialized) {
      throw new OpfsNotInitializedError();
    }

    switch (action) {
      case "opfs.listFiles": {
        postMessage({ id, action, result: await walk(root!) });
        return;
      }
      case "opfs.fileCount": {
        postMessage({ id, action, result: (await walk(root!)).length });
        return;
      }
      case "opfs.poolCapacity": {
        postMessage({ id, action, result: 1 });
        return;
      }
      case "opfs.fileExists": {
        postMessage({ id, action, result: await fileExists(data.path) });
        return;
      }
      case "opfs.deleteFile": {
        const exists = await fileExists(data.path);
        if (!exists) {
          postMessage({ id, action, result: false });
          return;
        }

        const { dir, fileName } = await getParentDirectory(data.path);
        await dir.removeEntry(fileName);
        postMessage({ id, action, result: true });
        return;
      }
      case "opfs.exportDb": {
        postMessage({ id, action, result: await readFile(data.path) });
        return;
      }
      case "opfs.importDb": {
        await writeFile(data.path, data.data);
        postMessage({ id, action, result: undefined });
        return;
      }
      case "opfs.clearAll": {
        for (const file of await walk(root!)) {
          const { dir, fileName } = await getParentDirectory(file);
          await dir.removeEntry(fileName);
        }
        postMessage({ id, action, result: undefined });
        return;
      }
    }
  } catch (error) {
    postMessage({
      id,
      action,
      error: error as Error,
    });
  }
};
