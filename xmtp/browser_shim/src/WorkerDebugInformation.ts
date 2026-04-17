import type { BrowserWorkerAction } from "./contracts";
import { WorkerBridge } from "./WorkerBridge";

export class WorkerDebugInformation {
  #bridge: WorkerBridge<BrowserWorkerAction>;

  constructor(bridge: WorkerBridge<BrowserWorkerAction>) {
    this.#bridge = bridge;
  }

  apiStatistics() {
    return this.#bridge.action("debugInformation.apiStatistics");
  }

  apiIdentityStatistics() {
    return this.#bridge.action("debugInformation.apiIdentityStatistics");
  }

  apiAggregateStatistics() {
    return this.#bridge.action("debugInformation.apiAggregateStatistics");
  }

  clearAllStatistics() {
    return this.#bridge.action("debugInformation.clearAllStatistics");
  }
}
