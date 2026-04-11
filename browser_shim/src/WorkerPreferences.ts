import type {
  BrowserWorkerAction,
  Consent,
  ConsentEntityType,
  ConsentState,
  InboxState,
  UserPreferenceUpdate,
} from "./contracts";
import { WorkerBridge } from "./WorkerBridge";
import { createStream, type StreamOptions } from "./streams";
import { uuid } from "./uuid";

export class WorkerPreferences {
  #bridge: WorkerBridge<BrowserWorkerAction>;

  constructor(bridge: WorkerBridge<BrowserWorkerAction>) {
    this.#bridge = bridge;
  }

  sync() {
    return this.#bridge.action("preferences.sync");
  }

  async inboxState(refreshFromNetwork: boolean) {
    return this.#bridge.action("preferences.inboxState", {
      refreshFromNetwork,
    });
  }

  async getInboxStates(inboxIds: string[], refreshFromNetwork = false) {
    return this.#bridge.action("preferences.getInboxStates", {
      inboxIds,
      refreshFromNetwork,
    });
  }

  async setConsentStates(records: Consent[]) {
    return this.#bridge.action("preferences.setConsentStates", { records });
  }

  async getConsentState(entityType: ConsentEntityType, entity: string) {
    return this.#bridge.action("preferences.getConsentState", {
      entityType,
      entity,
    });
  }

  async streamConsent(
    options?: StreamOptions<Consent[], Consent[]>,
  ) {
    const stream = async (
      callback: (error: Error | null, value: Consent[] | undefined) => void,
      onFail: () => void,
    ) => {
      const streamId = uuid();
      await this.#bridge.action("preferences.streamConsent", { streamId });
      return this.#bridge.handleStreamMessage(streamId, callback, {
        onFail,
      }) as unknown as () => void;
    };

    return createStream(stream, undefined, options);
  }

  async streamPreferences(
    options?: StreamOptions<UserPreferenceUpdate[], UserPreferenceUpdate[]>,
  ) {
    const stream = async (
      callback: (
        error: Error | null,
        value: UserPreferenceUpdate[] | undefined,
      ) => void,
      onFail: () => void,
    ) => {
      const streamId = uuid();
      await this.#bridge.action("preferences.streamPreferences", { streamId });
      return this.#bridge.handleStreamMessage(streamId, callback, {
        onFail,
      }) as unknown as () => void;
    };

    return createStream(stream, undefined, options);
  }
}
