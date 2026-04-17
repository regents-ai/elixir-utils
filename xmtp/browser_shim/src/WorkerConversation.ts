import type {
  Actions,
  Attachment,
  BrowserWorkerAction,
  ConsentState,
  ConversationDebugInfo,
  DecodedMessage,
  EncodedContent,
  GroupMember,
  HmacKeys,
  Identifier,
  Intent,
  LastReadTimes,
  ListMessagesOptions,
  Message,
  MetadataField,
  MultiRemoteAttachment,
  PermissionPolicy,
  PermissionUpdateType,
  Reaction,
  RemoteAttachment,
  Reply,
  SafeConversation,
  SendMessageOpts,
  TransactionReference,
  WalletSendCalls,
} from "./contracts";
import { WorkerBridge } from "./WorkerBridge";
import { createStream, type StreamOptions } from "./streams";
import { uuid } from "./uuid";

export class WorkerConversation {
  #bridge: WorkerBridge<BrowserWorkerAction>;
  #conversation: SafeConversation;

  constructor(bridge: WorkerBridge<BrowserWorkerAction>, conversation: SafeConversation) {
    this.#bridge = bridge;
    this.#conversation = conversation;
  }

  get snapshot() {
    return this.#conversation;
  }

  get id() {
    return this.#conversation.id;
  }

  get name() {
    return this.#conversation.name;
  }

  async updateName(name: string) {
    return this.#bridge.action("group.updateName", {
      id: this.id,
      name,
    });
  }

  get imageUrl() {
    return this.#conversation.imageUrl;
  }

  async updateImageUrl(imageUrl: string) {
    return this.#bridge.action("group.updateImageUrl", {
      id: this.id,
      imageUrl,
    });
  }

  get description() {
    return this.#conversation.description;
  }

  async updateDescription(description: string) {
    return this.#bridge.action("group.updateDescription", {
      id: this.id,
      description,
    });
  }

  get appData() {
    return this.#conversation.appData;
  }

  async updateAppData(appData: string) {
    return this.#bridge.action("group.updateAppData", {
      id: this.id,
      appData,
    });
  }

  get isActive() {
    return this.#bridge.action("conversation.isActive", { id: this.id });
  }

  get addedByInboxId() {
    return this.#conversation.addedByInboxId;
  }

  get createdAtNs() {
    return this.#conversation.createdAtNs;
  }

  get createdAt() {
    return this.#conversation.createdAtNs
      ? new Date(Number(this.#conversation.createdAtNs / 1_000_000n))
      : undefined;
  }

  async lastMessage() {
    return this.#bridge.action("conversation.lastMessage", { id: this.id });
  }

  async metadata() {
    return this.#conversation.metadata;
  }

  async members() {
    return this.#bridge.action("conversation.members", { id: this.id });
  }

  listAdmins() {
    return this.#bridge.action("group.listAdmins", { id: this.id });
  }

  listSuperAdmins() {
    return this.#bridge.action("group.listSuperAdmins", { id: this.id });
  }

  permissions() {
    return this.#bridge.action("group.permissions", { id: this.id });
  }

  async updatePermission(
    permissionType: PermissionUpdateType,
    policy: PermissionPolicy,
    metadataField?: MetadataField,
  ) {
    return this.#bridge.action("group.updatePermission", {
      id: this.id,
      permissionType,
      policy,
      metadataField,
    });
  }

  isAdmin(inboxId: string) {
    return this.#bridge.action("group.isAdmin", {
      id: this.id,
      inboxId,
    });
  }

  isSuperAdmin(inboxId: string) {
    return this.#bridge.action("group.isSuperAdmin", {
      id: this.id,
      inboxId,
    });
  }

  async sync() {
    const conversation = await this.#bridge.action("conversation.sync", {
      id: this.id,
    });
    this.#conversation = conversation;
    return conversation;
  }

  async addMembersByIdentifiers(identifiers: Identifier[]) {
    return this.#bridge.action("group.addMembersByIdentifiers", {
      id: this.id,
      identifiers,
    });
  }

  async addMembers(inboxIds: string[]) {
    return this.#bridge.action("group.addMembers", {
      id: this.id,
      inboxIds,
    });
  }

  async removeMembersByIdentifiers(identifiers: Identifier[]) {
    return this.#bridge.action("group.removeMembersByIdentifiers", {
      id: this.id,
      identifiers,
    });
  }

  async removeMembers(inboxIds: string[]) {
    return this.#bridge.action("group.removeMembers", {
      id: this.id,
      inboxIds,
    });
  }

  async addAdmin(inboxId: string) {
    return this.#bridge.action("group.addAdmin", {
      id: this.id,
      inboxId,
    });
  }

  async removeAdmin(inboxId: string) {
    return this.#bridge.action("group.removeAdmin", {
      id: this.id,
      inboxId,
    });
  }

  async addSuperAdmin(inboxId: string) {
    return this.#bridge.action("group.addSuperAdmin", {
      id: this.id,
      inboxId,
    });
  }

  async removeSuperAdmin(inboxId: string) {
    return this.#bridge.action("group.removeSuperAdmin", {
      id: this.id,
      inboxId,
    });
  }

  async publishMessages() {
    return this.#bridge.action("conversation.publishMessages", { id: this.id });
  }

  async processStreamedMessage(envelopeBytes: Uint8Array) {
    return this.#bridge.action("conversation.processStreamedMessage", {
      id: this.id,
      envelopeBytes,
    });
  }

  async send(encodedContent: EncodedContent, options?: SendMessageOpts) {
    return this.#bridge.action("conversation.send", {
      id: this.id,
      content: encodedContent,
      options,
    });
  }

  async sendText(text: string, isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendText", {
      id: this.id,
      text,
      isOptimistic,
    });
  }

  async sendMarkdown(markdown: string, isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendMarkdown", {
      id: this.id,
      markdown,
      isOptimistic,
    });
  }

  async sendReaction(reaction: Reaction, isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendReaction", {
      id: this.id,
      reaction,
      isOptimistic,
    });
  }

  async sendReadReceipt(isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendReadReceipt", {
      id: this.id,
      isOptimistic,
    });
  }

  async sendReply(reply: Reply, isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendReply", {
      id: this.id,
      reply,
      isOptimistic,
    });
  }

  async sendTransactionReference(
    transactionReference: TransactionReference,
    isOptimistic?: boolean,
  ) {
    return this.#bridge.action("conversation.sendTransactionReference", {
      id: this.id,
      transactionReference,
      isOptimistic,
    });
  }

  async sendWalletSendCalls(
    walletSendCalls: WalletSendCalls,
    isOptimistic?: boolean,
  ) {
    return this.#bridge.action("conversation.sendWalletSendCalls", {
      id: this.id,
      walletSendCalls,
      isOptimistic,
    });
  }

  async sendActions(actions: Actions, isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendActions", {
      id: this.id,
      actions,
      isOptimistic,
    });
  }

  async sendIntent(intent: Intent, isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendIntent", {
      id: this.id,
      intent,
      isOptimistic,
    });
  }

  async sendAttachment(attachment: Attachment, isOptimistic?: boolean) {
    return this.#bridge.action("conversation.sendAttachment", {
      id: this.id,
      attachment,
      isOptimistic,
    });
  }

  async sendMultiRemoteAttachment(
    multiRemoteAttachment: MultiRemoteAttachment,
    isOptimistic?: boolean,
  ) {
    return this.#bridge.action("conversation.sendMultiRemoteAttachment", {
      id: this.id,
      multiRemoteAttachment,
      isOptimistic,
    });
  }

  async sendRemoteAttachment(
    remoteAttachment: RemoteAttachment,
    isOptimistic?: boolean,
  ) {
    return this.#bridge.action("conversation.sendRemoteAttachment", {
      id: this.id,
      remoteAttachment,
      isOptimistic,
    });
  }

  async messages(options?: ListMessagesOptions): Promise<DecodedMessage[]> {
    return this.#bridge.action("conversation.messages", {
      id: this.id,
      options,
    });
  }

  async countMessages(options?: ListMessagesOptions) {
    return this.#bridge.action("conversation.countMessages", {
      id: this.id,
      options,
    });
  }

  consentState() {
    return this.#bridge.action("conversation.consentState", { id: this.id });
  }

  updateConsentState(state: ConsentState) {
    return this.#bridge.action("conversation.updateConsentState", {
      id: this.id,
      state,
    });
  }

  dmPeerInboxId() {
    return this.#bridge.action("dm.peerInboxId", { id: this.id });
  }

  messageDisappearingSettings() {
    return this.#bridge.action("conversation.messageDisappearingSettings", {
      id: this.id,
    });
  }

  async updateMessageDisappearingSettings(fromNs: bigint, inNs: bigint) {
    return this.#bridge.action("conversation.updateMessageDisappearingSettings", {
      id: this.id,
      fromNs,
      inNs,
    });
  }

  async removeMessageDisappearingSettings() {
    return this.#bridge.action("conversation.removeMessageDisappearingSettings", {
      id: this.id,
    });
  }

  isMessageDisappearingEnabled() {
    return this.#bridge.action("conversation.isMessageDisappearingEnabled", {
      id: this.id,
    });
  }

  async stream(
    options?: StreamOptions<DecodedMessage, DecodedMessage>,
  ) {
    const stream = async (
      callback: (error: Error | null, value: DecodedMessage | undefined) => void,
      onFail: () => void,
    ) => {
      const streamId = uuid();
      if (!options?.disableSync) {
        await this.sync();
      }
      await this.#bridge.action("conversation.stream", {
        groupId: this.id,
        streamId,
      });
      return this.#bridge.handleStreamMessage(streamId, callback, {
        ...options,
        onFail,
      }) as unknown as () => void;
    };

    return createStream(stream, undefined, options);
  }

  pausedForVersion() {
    return this.#bridge.action("conversation.pausedForVersion", { id: this.id });
  }

  hmacKeys() {
    return this.#bridge.action("conversation.hmacKeys", { id: this.id });
  }

  async debugInfo() {
    return this.#bridge.action("conversation.debugInfo", { id: this.id });
  }

  async duplicateDms() {
    const dms = await this.#bridge.action("dm.duplicateDms", { id: this.id });
    return dms.map((conversation) => new WorkerConversation(this.#bridge, conversation));
  }

  async requestRemoval() {
    return this.#bridge.action("group.requestRemoval", { id: this.id });
  }

  isPendingRemoval() {
    return this.#bridge.action("group.isPendingRemoval", { id: this.id });
  }

  async lastReadTimes() {
    return this.#bridge.action("conversation.lastReadTimes", { id: this.id });
  }
}
