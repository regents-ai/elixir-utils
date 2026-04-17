import type { OpfsAction } from "./contracts";
import { WorkerBridge } from "./WorkerBridge";

export interface OpfsTransport {
  action<A extends OpfsAction["action"]>(
    action: A,
    ...args: Extract<OpfsAction, { action: A }>["data"] extends undefined
      ? []
      : [data: Extract<OpfsAction, { action: A }>["data"]]
  ): Promise<Extract<OpfsAction, { action: A }>["result"]>;
  close(): void;
}

export class Opfs {
  #bridge: OpfsTransport;

  constructor(bridge: OpfsTransport) {
    this.#bridge = bridge;
  }

  static async create(enableLogging?: boolean) {
    const worker = new Worker(new URL("./workers/opfs", import.meta.url), {
      type: "module",
    });
    const bridge = new WorkerBridge<OpfsAction>(worker, enableLogging);
    const opfs = new Opfs(bridge as unknown as OpfsTransport);
    await opfs.init(enableLogging);
    return opfs;
  }

  async init(enableLogging?: boolean) {
    return this.#bridge.action("opfs.init", {
      enableLogging,
    });
  }

  close() {
    this.#bridge.close();
  }

  listFiles() {
    return this.#bridge.action("opfs.listFiles");
  }

  fileCount() {
    return this.#bridge.action("opfs.fileCount");
  }

  poolCapacity() {
    return this.#bridge.action("opfs.poolCapacity");
  }

  fileExists(path: string) {
    return this.#bridge.action("opfs.fileExists", { path });
  }

  deleteFile(path: string) {
    return this.#bridge.action("opfs.deleteFile", { path });
  }

  exportDb(path: string) {
    return this.#bridge.action("opfs.exportDb", { path });
  }

  importDb(path: string, data: Uint8Array) {
    return this.#bridge.action("opfs.importDb", { path, data });
  }

  clearAll() {
    return this.#bridge.action("opfs.clearAll");
  }
}
