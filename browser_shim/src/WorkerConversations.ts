import type {
  BrowserWorkerAction,
  ConsentState,
  ConversationType,
  CreateDmOptions,
  CreateGroupOptions,
  DecodedMessage,
  Identifier,
  ListConversationsOptions,
  SafeConversation,
} from "./contracts";
import { WorkerBridge } from "./WorkerBridge";
import { createStream, type StreamCallback, type StreamOptions } from "./streams";
import { uuid } from "./uuid";
import { WorkerConversation } from "./WorkerConversation";

export class WorkerConversations {
  #bridge: WorkerBridge<BrowserWorkerAction>;

  constructor(bridge: WorkerBridge<BrowserWorkerAction>) {
    this.#bridge = bridge;
  }

  sync() {
    return this.#bridge.action("conversations.sync");
  }

  async syncAll(consentStates?: ConsentState[]) {
    return this.#bridge.action("conversations.syncAll", { consentStates });
  }

  getConversationById(id: string) {
    return this.#bridge.action("conversations.getConversationById", { id }).then((conversation) =>
      conversation ? new WorkerConversation(this.#bridge, conversation) : undefined,
    );
  }

  async getMessageById(id: string): Promise<DecodedMessage | undefined> {
    return this.#bridge.action("conversations.getMessageById", { id });
  }

  getDmByInboxId(inboxId: string) {
    return this.#bridge.action("conversations.getDmByInboxId", { inboxId }).then((conversation) =>
      conversation ? new WorkerConversation(this.#bridge, conversation) : undefined,
    );
  }

  list(options?: ListConversationsOptions) {
    return this.#bridge.action("conversations.list", { options }).then((conversations) =>
      conversations.map((conversation) => new WorkerConversation(this.#bridge, conversation)),
    );
  }

  listGroups(options?: Omit<ListConversationsOptions, "conversationType">) {
    return this.#bridge.action("conversations.listGroups", { options }).then((conversations) =>
      conversations.map((conversation) => new WorkerConversation(this.#bridge, conversation)),
    );
  }

  listDms(options?: Omit<ListConversationsOptions, "conversationType">) {
    return this.#bridge.action("conversations.listDms", { options }).then((conversations) =>
      conversations.map((conversation) => new WorkerConversation(this.#bridge, conversation)),
    );
  }

  createGroupOptimistic(options?: CreateGroupOptions) {
    return this.#bridge.action("conversations.createGroupOptimistic", { options }).then(
      (conversation) => new WorkerConversation(this.#bridge, conversation),
    );
  }

  async createGroupWithIdentifiers(
    identifiers: Identifier[],
    options?: CreateGroupOptions,
  ) {
    const conversation = await this.#bridge.action("conversations.createGroupWithIdentifiers", {
      identifiers,
      options,
    });
    return new WorkerConversation(this.#bridge, conversation);
  }

  async createGroup(inboxIds: string[], options?: CreateGroupOptions) {
    const conversation = await this.#bridge.action("conversations.createGroup", {
      inboxIds,
      options,
    });
    return new WorkerConversation(this.#bridge, conversation);
  }

  async createDmWithIdentifier(
    identifier: Identifier,
    options?: CreateDmOptions,
  ) {
    const conversation = await this.#bridge.action("conversations.createDmWithIdentifier", {
      identifier,
      options,
    });
    return new WorkerConversation(this.#bridge, conversation);
  }

  async createDm(inboxId: string, options?: CreateDmOptions) {
    const conversation = await this.#bridge.action("conversations.createDm", {
      inboxId,
      options,
    });
    return new WorkerConversation(this.#bridge, conversation);
  }

  hmacKeys() {
    return this.#bridge.action("conversations.hmacKeys");
  }

  async stream<T extends WorkerConversation = WorkerConversation>(
    options?: StreamOptions<SafeConversation, T> & {
      conversationType?: ConversationType;
    },
  ) {
    const stream = async (
      callback: StreamCallback<SafeConversation>,
      onFail: () => void,
    ) => {
      const streamId = uuid();
      if (!options?.disableSync) {
        await this.sync();
      }
      await this.#bridge.action("conversations.stream", {
        streamId,
        conversationType: options?.conversationType,
      });
      return this.#bridge.handleStreamMessage(streamId, callback, {
        ...options,
        onFail,
      }) as unknown as () => void;
    };

    const convertConversation = (value: SafeConversation) =>
      new WorkerConversation(this.#bridge, value) as T;

    return createStream(stream, convertConversation, options);
  }

  async streamGroups(options?: StreamOptions<SafeConversation, WorkerConversation>) {
    return this.stream({
      ...options,
      conversationType: "group",
    });
  }

  async streamDms(options?: StreamOptions<SafeConversation, WorkerConversation>) {
    return this.stream({
      ...options,
      conversationType: "dm",
    });
  }

  async streamAllMessages(
    options?: StreamOptions<DecodedMessage, DecodedMessage> & {
      conversationType?: ConversationType;
      consentStates?: ConsentState[];
    },
  ) {
    const stream = async (
      callback: StreamCallback<DecodedMessage>,
      onFail: () => void,
    ) => {
      const streamId = uuid();
      if (!options?.disableSync) {
        await this.sync();
      }
      await this.#bridge.action("conversations.streamAllMessages", {
        streamId,
        conversationType: options?.conversationType,
        consentStates: options?.consentStates,
      });
      return this.#bridge.handleStreamMessage(streamId, callback, {
        ...options,
        onFail,
      }) as unknown as () => void;
    };

    return createStream(stream, undefined, options);
  }

  async streamAllGroupMessages(
    options?: StreamOptions<DecodedMessage, DecodedMessage> & {
      consentStates?: ConsentState[];
    },
  ) {
    const stream = async (
      callback: StreamCallback<DecodedMessage>,
      onFail: () => void,
    ) => {
      const streamId = uuid();
      if (!options?.disableSync) {
        await this.sync();
      }
      await this.#bridge.action("conversations.streamAllGroupMessages", {
        streamId,
        consentStates: options?.consentStates,
      });
      return this.#bridge.handleStreamMessage(streamId, callback, {
        ...options,
        onFail,
      }) as unknown as () => void;
    };

    return createStream(stream, undefined, options);
  }

  async streamAllDmMessages(
    options?: StreamOptions<DecodedMessage, DecodedMessage> & {
      consentStates?: ConsentState[];
    },
  ) {
    const stream = async (
      callback: StreamCallback<DecodedMessage>,
      onFail: () => void,
    ) => {
      const streamId = uuid();
      if (!options?.disableSync) {
        await this.sync();
      }
      await this.#bridge.action("conversations.streamAllDmMessages", {
        streamId,
        consentStates: options?.consentStates,
      });
      return this.#bridge.handleStreamMessage(streamId, callback, {
        ...options,
        onFail,
      }) as unknown as () => void;
    };

    return createStream(stream, undefined, options);
  }

  async streamDeletedMessages(
    options?: Omit<
      StreamOptions<DecodedMessage, DecodedMessage>,
      | "disableSync"
      | "onFail"
      | "onRetry"
      | "onRestart"
      | "retryAttempts"
      | "retryDelay"
      | "retryOnFail"
    >,
  ) {
    const stream = async (callback: StreamCallback<DecodedMessage>) => {
      const streamId = uuid();
      await this.#bridge.action("conversations.streamDeletedMessages", {
        streamId,
      });
      return this.#bridge.handleStreamMessage(streamId, callback, options) as unknown as () => void;
    };

    return createStream(stream, undefined, options);
  }

}
