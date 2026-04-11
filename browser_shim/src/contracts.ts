export type UnknownAction = {
  action: string;
  id: string;
  data: unknown;
  result: unknown;
};

export type ActionName<T extends UnknownAction> = T["action"];

export type ExtractAction<
  T extends UnknownAction,
  A extends ActionName<T>,
> = Extract<T, { action: A }>;

export type ExtractActionData<
  T extends UnknownAction,
  A extends ActionName<T>,
> = ExtractAction<T, A>["data"];

export type ExtractActionResult<
  T extends UnknownAction,
  A extends ActionName<T>,
> = ExtractAction<T, A>["result"];

export type ActionWithoutData<T extends UnknownAction> = {
  [A in T["action"]]: Omit<Extract<T, { action: A }>, "data">;
}[T["action"]];

export type ActionWithoutResult<T extends UnknownAction> = {
  [A in T["action"]]: Omit<Extract<T, { action: A }>, "result">;
}[T["action"]];

export type ActionErrorData<T extends UnknownAction> = {
  id: string;
  action: ActionName<T>;
  error: Error;
};

export type XmtpEnv =
  | "local"
  | "dev"
  | "production"
  | "testnet-staging"
  | "testnet-dev"
  | "testnet"
  | "mainnet";

export type Identifier = {
  kind?: string;
  identifier?: string;
  address?: string;
  username?: string;
  [key: string]: unknown;
};

export type ClientOptions = {
  env?: XmtpEnv;
  apiUrl?: string;
  gatewayHost?: string;
  appVersion?: string;
  dbPath?: string;
  loggingLevel?: number;
  enableLogging?: boolean;
};

export type SafeSigner = {
  type: "EOA" | "SCW";
  identifier?: Identifier;
  signature?: Uint8Array | string;
  chainId?: number | bigint;
  blockNumber?: number | bigint;
  [key: string]: unknown;
};

export type SignatureRequestHandle = {
  signatureText(): Promise<string>;
  addEcdsaSignature?(signature: Uint8Array): Promise<void>;
  addScwSignature?(
    identifier: Identifier,
    signature: Uint8Array,
    chainId?: number | bigint,
    blockNumber?: number | bigint,
  ): Promise<void>;
};

export type ArchiveOptions = Record<string, unknown>;
export type AvailableArchiveInfo = Record<string, unknown>;
export type ArchiveMetadata = Record<string, unknown>;
export type GroupSyncSummary = Record<string, unknown>;
export type KeyPackageStatus = string | Record<string, unknown>;

export type Conversation = Record<string, unknown>;
export type DecodedMessage = Record<string, unknown>;
export type Consent = Record<string, unknown>;
export type UserPreferenceUpdate = Record<string, unknown>;

export type EndStreamAction = {
  action: "endStream";
  id: string;
  result: undefined;
  data: {
    streamId: string;
  };
};

export const clientActionNames = [
  "client.init",
  "client.applySignatureRequest",
  "client.createInboxSignatureText",
  "client.addAccountSignatureText",
  "client.removeAccountSignatureText",
  "client.revokeAllOtherInstallationsSignatureText",
  "client.revokeInstallationsSignatureText",
  "client.changeRecoveryIdentifierSignatureText",
  "client.registerIdentity",
  "client.addAccount",
  "client.removeAccount",
  "client.revokeAllOtherInstallations",
  "client.changeRecoveryIdentifier",
  "client.revokeInstallations",
  "client.isRegistered",
  "client.canMessage",
  "client.getInboxIdByIdentifier",
  "client.signWithInstallationKey",
  "client.verifySignedWithInstallationKey",
  "client.verifySignedWithPublicKey",
  "client.fetchKeyPackageStatuses",
  "client.sendSyncRequest",
  "client.sendSyncArchive",
  "client.processSyncArchive",
  "client.listAvailableArchives",
  "client.createArchive",
  "client.importArchive",
  "client.archiveMetadata",
  "client.syncAllDeviceSyncGroups",
] as const;

export type ClientActionName = (typeof clientActionNames)[number];

export type ClientAction =
  | {
      action: "client.init";
      id: string;
      result: {
        accountIdentifier: Identifier;
        appVersion: string;
        env: XmtpEnv;
        inboxId: string;
        installationId: string;
        installationIdBytes: Uint8Array;
        libxmtpVersion: string;
      };
      data: {
        identifier: Identifier;
        options?: ClientOptions;
      };
    }
  | {
      action: "client.applySignatureRequest";
      id: string;
      result: undefined;
      data: {
        signer: SafeSigner;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.createInboxSignatureText";
      id: string;
      result: {
        signatureText?: string;
        signatureRequestId?: string;
      };
      data: {
        signatureRequestId: string;
      };
    }
  | {
      action: "client.addAccountSignatureText";
      id: string;
      result: {
        signatureText: string;
        signatureRequestId: string;
      };
      data: {
        newIdentifier: Identifier;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.removeAccountSignatureText";
      id: string;
      result: {
        signatureText: string;
        signatureRequestId: string;
      };
      data: {
        identifier: Identifier;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.revokeAllOtherInstallationsSignatureText";
      id: string;
      result: {
        signatureText: string | undefined;
        signatureRequestId: string;
      };
      data: {
        signatureRequestId: string;
      };
    }
  | {
      action: "client.revokeInstallationsSignatureText";
      id: string;
      result: {
        signatureText: string;
        signatureRequestId: string;
      };
      data: {
        installationIds: Uint8Array[];
        signatureRequestId: string;
      };
    }
  | {
      action: "client.changeRecoveryIdentifierSignatureText";
      id: string;
      result: {
        signatureText: string;
        signatureRequestId: string;
      };
      data: {
        identifier: Identifier;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.registerIdentity";
      id: string;
      result: undefined;
      data: {
        signer: SafeSigner;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.addAccount";
      id: string;
      result: undefined;
      data: {
        identifier: Identifier;
        signer: SafeSigner;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.removeAccount";
      id: string;
      result: undefined;
      data: {
        identifier: Identifier;
        signer: SafeSigner;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.revokeAllOtherInstallations";
      id: string;
      result: undefined;
      data: {
        signer: SafeSigner;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.changeRecoveryIdentifier";
      id: string;
      result: undefined;
      data: {
        identifier: Identifier;
        signer: SafeSigner;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.revokeInstallations";
      id: string;
      result: undefined;
      data: {
        installationIds: Uint8Array[];
        signer: SafeSigner;
        signatureRequestId: string;
      };
    }
  | {
      action: "client.isRegistered";
      id: string;
      result: boolean;
      data: undefined;
    }
  | {
      action: "client.canMessage";
      id: string;
      result: Map<string, boolean>;
      data: {
        identifiers: Identifier[];
      };
    }
  | {
      action: "client.getInboxIdByIdentifier";
      id: string;
      result: string | undefined;
      data: {
        identifier: Identifier;
      };
    }
  | {
      action: "client.signWithInstallationKey";
      id: string;
      result: Uint8Array;
      data: {
        signatureText: string;
      };
    }
  | {
      action: "client.verifySignedWithInstallationKey";
      id: string;
      result: boolean;
      data: {
        signatureText: string;
        signatureBytes: Uint8Array;
      };
    }
  | {
      action: "client.verifySignedWithPublicKey";
      id: string;
      result: boolean;
      data: {
        signatureText: string;
        signatureBytes: Uint8Array;
        publicKey: Uint8Array;
      };
    }
  | {
      action: "client.fetchKeyPackageStatuses";
      id: string;
      result: Map<string, KeyPackageStatus>;
      data: {
        installationIds: string[];
      };
    }
  | {
      action: "client.sendSyncRequest";
      id: string;
      result: undefined;
      data: {
        options: ArchiveOptions;
        serverUrl: string;
      };
    }
  | {
      action: "client.sendSyncArchive";
      id: string;
      result: undefined;
      data: {
        options: ArchiveOptions;
        serverUrl: string;
        pin: string;
      };
    }
  | {
      action: "client.processSyncArchive";
      id: string;
      result: undefined;
      data: {
        archivePin?: string | null;
      };
    }
  | {
      action: "client.listAvailableArchives";
      id: string;
      result: AvailableArchiveInfo[];
      data: {
        daysCutoff: number;
      };
    }
  | {
      action: "client.createArchive";
      id: string;
      result: Uint8Array;
      data: {
        opts: ArchiveOptions;
        key: Uint8Array;
      };
    }
  | {
      action: "client.importArchive";
      id: string;
      result: undefined;
      data: {
        data: Uint8Array;
        key: Uint8Array;
      };
    }
  | {
      action: "client.archiveMetadata";
      id: string;
      result: ArchiveMetadata;
      data: {
        data: Uint8Array;
        key: Uint8Array;
      };
    }
  | {
      action: "client.syncAllDeviceSyncGroups";
      id: string;
      result: GroupSyncSummary;
      data: undefined;
    };

export const clientWorkerActionNames = [
  ...clientActionNames,
  "endStream",
] as const;

export type ClientWorkerActionName = (typeof clientWorkerActionNames)[number];

export type ClientWorkerAction = ClientAction | EndStreamAction;

export const streamActionNames = [
  "stream.message",
  "stream.conversation",
  "stream.consent",
  "stream.preferences",
  "stream.deletedMessage",
  "stream.fail",
] as const;

export type StreamActionName = (typeof streamActionNames)[number];

export type StreamAction =
  | {
      action: "stream.message";
      streamId: string;
      result: DecodedMessage | undefined;
    }
  | {
      action: "stream.conversation";
      streamId: string;
      result: Conversation | undefined;
    }
  | {
      action: "stream.consent";
      streamId: string;
      result: Consent[] | undefined;
    }
  | {
      action: "stream.preferences";
      streamId: string;
      result: UserPreferenceUpdate[] | undefined;
    }
  | {
      action: "stream.deletedMessage";
      streamId: string;
      result: DecodedMessage | undefined;
    }
  | {
      action: "stream.fail";
      streamId: string;
      result: undefined;
    };

export type StreamActionErrorData = {
  action: StreamActionName;
  error: Error;
  streamId: string;
};

export const opfsActionNames = [
  "opfs.init",
  "opfs.listFiles",
  "opfs.fileCount",
  "opfs.poolCapacity",
  "opfs.fileExists",
  "opfs.deleteFile",
  "opfs.exportDb",
  "opfs.importDb",
  "opfs.clearAll",
] as const;

export type OpfsActionName = (typeof opfsActionNames)[number];

export type OpfsAction =
  | {
      action: "opfs.init";
      id: string;
      result: void;
      data: {
        enableLogging?: boolean;
      };
    }
  | {
      action: "opfs.listFiles";
      id: string;
      result: string[];
      data: undefined;
    }
  | {
      action: "opfs.fileCount";
      id: string;
      result: number;
      data: undefined;
    }
  | {
      action: "opfs.poolCapacity";
      id: string;
      result: number;
      data: undefined;
    }
  | {
      action: "opfs.fileExists";
      id: string;
      result: boolean;
      data: {
        path: string;
      };
    }
  | {
      action: "opfs.deleteFile";
      id: string;
      result: boolean;
      data: {
        path: string;
      };
    }
  | {
      action: "opfs.exportDb";
      id: string;
      result: Uint8Array;
      data: {
        path: string;
      };
    }
  | {
      action: "opfs.importDb";
      id: string;
      result: void;
      data: {
        path: string;
        data: Uint8Array;
      };
    }
  | {
      action: "opfs.clearAll";
      id: string;
      result: void;
      data: undefined;
    };

export type ConversationType = "group" | "dm";
export type ConsentState = string;
export type ConsentEntityType = string;
export type PermissionPolicy = string;
export type PermissionUpdateType = string;
export type MetadataField = string;

export type GroupPermissions = {
  policyType: string;
  policySet: Record<string, unknown>;
};

export type SafeConversation = {
  id: string;
  name: string;
  imageUrl: string;
  description: string;
  appData: string;
  permissions: GroupPermissions;
  addedByInboxId: string;
  metadata: Record<string, unknown>;
  admins: string[];
  superAdmins: string[];
  createdAtNs: bigint;
  isActive?: boolean;
  membershipState?: string;
  dmPeerInboxId?: string;
};

export type ConversationDebugInfo = Record<string, unknown>;
export type InboxState = Record<string, unknown>;
export type Message = Record<string, unknown>;
export type GroupMember = Record<string, unknown>;
export type HmacKeys = Map<string, unknown[]>;
export type LastReadTimes = Map<string, bigint>;

export type ListMessagesOptions = Record<string, unknown>;
export type ListConversationsOptions = Record<string, unknown>;
export type CreateDmOptions = Record<string, unknown>;
export type CreateGroupOptions = Record<string, unknown>;
export type SendMessageOpts = Record<string, unknown>;
export type EncodedContent = Record<string, unknown>;
export type Actions = Record<string, unknown>;
export type Attachment = Record<string, unknown>;
export type Intent = Record<string, unknown>;
export type MultiRemoteAttachment = Record<string, unknown>;
export type Reaction = Record<string, unknown>;
export type RemoteAttachment = Record<string, unknown>;
export type Reply = Record<string, unknown>;
export type TransactionReference = Record<string, unknown>;
export type WalletSendCalls = Record<string, unknown>;

export const conversationActionNames = [
  "conversation.sync",
  "conversation.send",
  "conversation.publishMessages",
  "conversation.processStreamedMessage",
  "conversation.messages",
  "conversation.countMessages",
  "conversation.members",
  "conversation.messageDisappearingSettings",
  "conversation.updateMessageDisappearingSettings",
  "conversation.removeMessageDisappearingSettings",
  "conversation.isMessageDisappearingEnabled",
  "conversation.stream",
  "conversation.pausedForVersion",
  "conversation.hmacKeys",
  "conversation.debugInfo",
  "conversation.consentState",
  "conversation.updateConsentState",
  "conversation.lastMessage",
  "conversation.isActive",
  "conversation.lastReadTimes",
  "conversation.sendText",
  "conversation.sendMarkdown",
  "conversation.sendReaction",
  "conversation.sendReadReceipt",
  "conversation.sendReply",
  "conversation.sendTransactionReference",
  "conversation.sendWalletSendCalls",
  "conversation.sendActions",
  "conversation.sendIntent",
  "conversation.sendAttachment",
  "conversation.sendMultiRemoteAttachment",
  "conversation.sendRemoteAttachment",
] as const;

export type ConversationActionName = (typeof conversationActionNames)[number];

export type ConversationAction =
  | {
      action: "conversation.sync";
      id: string;
      result: SafeConversation;
      data: { id: string };
    }
  | {
      action: "conversation.send";
      id: string;
      result: string;
      data: { id: string; content: EncodedContent; options?: SendMessageOpts };
    }
  | {
      action: "conversation.publishMessages";
      id: string;
      result: undefined;
      data: { id: string };
    }
  | {
      action: "conversation.processStreamedMessage";
      id: string;
      result: Message[];
      data: { id: string; envelopeBytes: Uint8Array };
    }
  | {
      action: "conversation.messages";
      id: string;
      result: DecodedMessage[];
      data: { id: string; options?: ListMessagesOptions };
    }
  | {
      action: "conversation.countMessages";
      id: string;
      result: bigint;
      data: { id: string; options?: Omit<ListMessagesOptions, "limit" | "direction"> };
    }
  | {
      action: "conversation.members";
      id: string;
      result: GroupMember[];
      data: { id: string };
    }
  | {
      action: "conversation.messageDisappearingSettings";
      id: string;
      result: { fromNs: bigint; inNs: bigint } | undefined;
      data: { id: string };
    }
  | {
      action: "conversation.updateMessageDisappearingSettings";
      id: string;
      result: undefined;
      data: { id: string; fromNs: bigint; inNs: bigint };
    }
  | {
      action: "conversation.removeMessageDisappearingSettings";
      id: string;
      result: undefined;
      data: { id: string };
    }
  | {
      action: "conversation.isMessageDisappearingEnabled";
      id: string;
      result: boolean;
      data: { id: string };
    }
  | {
      action: "conversation.stream";
      id: string;
      result: undefined;
      data: { groupId: string; streamId: string };
    }
  | {
      action: "conversation.pausedForVersion";
      id: string;
      result: string | undefined;
      data: { id: string };
    }
  | {
      action: "conversation.hmacKeys";
      id: string;
      result: HmacKeys;
      data: { id: string };
    }
  | {
      action: "conversation.debugInfo";
      id: string;
      result: ConversationDebugInfo;
      data: { id: string };
    }
  | {
      action: "conversation.consentState";
      id: string;
      result: ConsentState;
      data: { id: string };
    }
  | {
      action: "conversation.updateConsentState";
      id: string;
      result: undefined;
      data: { id: string; state: ConsentState };
    }
  | {
      action: "conversation.lastMessage";
      id: string;
      result: DecodedMessage | undefined;
      data: { id: string };
    }
  | {
      action: "conversation.isActive";
      id: string;
      result: boolean;
      data: { id: string };
    }
  | {
      action: "conversation.lastReadTimes";
      id: string;
      result: LastReadTimes;
      data: { id: string };
    }
  | {
      action: "conversation.sendText";
      id: string;
      result: string;
      data: { id: string; text: string; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendMarkdown";
      id: string;
      result: string;
      data: { id: string; markdown: string; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendReaction";
      id: string;
      result: string;
      data: { id: string; reaction: Reaction; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendReadReceipt";
      id: string;
      result: string;
      data: { id: string; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendReply";
      id: string;
      result: string;
      data: { id: string; reply: Reply; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendTransactionReference";
      id: string;
      result: string;
      data: {
        id: string;
        transactionReference: TransactionReference;
        isOptimistic?: boolean;
      };
    }
  | {
      action: "conversation.sendWalletSendCalls";
      id: string;
      result: string;
      data: { id: string; walletSendCalls: WalletSendCalls; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendActions";
      id: string;
      result: string;
      data: { id: string; actions: Actions; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendIntent";
      id: string;
      result: string;
      data: { id: string; intent: Intent; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendAttachment";
      id: string;
      result: string;
      data: { id: string; attachment: Attachment; isOptimistic?: boolean };
    }
  | {
      action: "conversation.sendMultiRemoteAttachment";
      id: string;
      result: string;
      data: {
        id: string;
        multiRemoteAttachment: MultiRemoteAttachment;
        isOptimistic?: boolean;
      };
    }
  | {
      action: "conversation.sendRemoteAttachment";
      id: string;
      result: string;
      data: { id: string; remoteAttachment: RemoteAttachment; isOptimistic?: boolean };
    };

export const conversationsActionNames = [
  "conversations.getConversationById",
  "conversations.getMessageById",
  "conversations.getDmByInboxId",
  "conversations.list",
  "conversations.listGroups",
  "conversations.listDms",
  "conversations.createGroupOptimistic",
  "conversations.createGroupWithIdentifiers",
  "conversations.createGroup",
  "conversations.createDmWithIdentifier",
  "conversations.createDm",
  "conversations.sync",
  "conversations.syncAll",
  "conversations.hmacKeys",
  "conversations.stream",
  "conversations.streamAllMessages",
  "conversations.streamAllGroupMessages",
  "conversations.streamAllDmMessages",
  "conversations.streamDeletedMessages",
] as const;

export type ConversationsActionName = (typeof conversationsActionNames)[number];

export type ConversationsAction =
  | {
      action: "conversations.getConversationById";
      id: string;
      result: SafeConversation | undefined;
      data: { id: string };
    }
  | {
      action: "conversations.getMessageById";
      id: string;
      result: DecodedMessage | undefined;
      data: { id: string };
    }
  | {
      action: "conversations.getDmByInboxId";
      id: string;
      result: SafeConversation | undefined;
      data: { inboxId: string };
    }
  | {
      action: "conversations.list";
      id: string;
      result: SafeConversation[];
      data: { options?: ListConversationsOptions };
    }
  | {
      action: "conversations.listGroups";
      id: string;
      result: SafeConversation[];
      data: { options?: Omit<ListConversationsOptions, "conversationType"> };
    }
  | {
      action: "conversations.listDms";
      id: string;
      result: SafeConversation[];
      data: { options?: Omit<ListConversationsOptions, "conversationType"> };
    }
  | {
      action: "conversations.createGroupOptimistic";
      id: string;
      result: SafeConversation;
      data: { options?: CreateGroupOptions };
    }
  | {
      action: "conversations.createGroupWithIdentifiers";
      id: string;
      result: SafeConversation;
      data: { identifiers: Identifier[]; options?: CreateGroupOptions };
    }
  | {
      action: "conversations.createGroup";
      id: string;
      result: SafeConversation;
      data: { inboxIds: string[]; options?: CreateGroupOptions };
    }
  | {
      action: "conversations.createDmWithIdentifier";
      id: string;
      result: SafeConversation;
      data: { identifier: Identifier; options?: CreateDmOptions };
    }
  | {
      action: "conversations.createDm";
      id: string;
      result: SafeConversation;
      data: { inboxId: string; options?: CreateDmOptions };
    }
  | {
      action: "conversations.sync";
      id: string;
      result: undefined;
      data: undefined;
    }
  | {
      action: "conversations.syncAll";
      id: string;
      result: undefined;
      data: { consentStates?: ConsentState[] };
    }
  | {
      action: "conversations.hmacKeys";
      id: string;
      result: HmacKeys;
      data: undefined;
    }
  | {
      action: "conversations.stream";
      id: string;
      result: undefined;
      data: { streamId: string; conversationType?: ConversationType };
    }
  | {
      action: "conversations.streamAllMessages";
      id: string;
      result: undefined;
      data: {
        streamId: string;
        conversationType?: ConversationType;
        consentStates?: ConsentState[];
      };
    }
  | {
      action: "conversations.streamAllGroupMessages";
      id: string;
      result: undefined;
      data: {
        streamId: string;
        consentStates?: ConsentState[];
      };
    }
  | {
      action: "conversations.streamAllDmMessages";
      id: string;
      result: undefined;
      data: {
        streamId: string;
        consentStates?: ConsentState[];
      };
    }
  | {
      action: "conversations.streamDeletedMessages";
      id: string;
      result: undefined;
      data: { streamId: string };
    };

export const groupActionNames = [
  "group.listAdmins",
  "group.listSuperAdmins",
  "group.isAdmin",
  "group.isSuperAdmin",
  "group.addMembersByIdentifiers",
  "group.removeMembersByIdentifiers",
  "group.addMembers",
  "group.removeMembers",
  "group.addAdmin",
  "group.removeAdmin",
  "group.addSuperAdmin",
  "group.removeSuperAdmin",
  "group.updateName",
  "group.updateDescription",
  "group.updateImageUrl",
  "group.updateAppData",
  "group.updatePermission",
  "group.permissions",
  "group.requestRemoval",
  "group.isPendingRemoval",
] as const;

export type GroupActionName = (typeof groupActionNames)[number];

export type GroupAction =
  | {
      action: "group.listAdmins";
      id: string;
      result: string[];
      data: { id: string };
    }
  | {
      action: "group.listSuperAdmins";
      id: string;
      result: string[];
      data: { id: string };
    }
  | {
      action: "group.isAdmin";
      id: string;
      result: boolean;
      data: { id: string; inboxId: string };
    }
  | {
      action: "group.isSuperAdmin";
      id: string;
      result: boolean;
      data: { id: string; inboxId: string };
    }
  | {
      action: "group.addMembersByIdentifiers";
      id: string;
      result: undefined;
      data: { id: string; identifiers: Identifier[] };
    }
  | {
      action: "group.removeMembersByIdentifiers";
      id: string;
      result: undefined;
      data: { id: string; identifiers: Identifier[] };
    }
  | {
      action: "group.addMembers";
      id: string;
      result: undefined;
      data: { id: string; inboxIds: string[] };
    }
  | {
      action: "group.removeMembers";
      id: string;
      result: undefined;
      data: { id: string; inboxIds: string[] };
    }
  | {
      action: "group.addAdmin";
      id: string;
      result: undefined;
      data: { id: string; inboxId: string };
    }
  | {
      action: "group.removeAdmin";
      id: string;
      result: undefined;
      data: { id: string; inboxId: string };
    }
  | {
      action: "group.addSuperAdmin";
      id: string;
      result: undefined;
      data: { id: string; inboxId: string };
    }
  | {
      action: "group.removeSuperAdmin";
      id: string;
      result: undefined;
      data: { id: string; inboxId: string };
    }
  | {
      action: "group.updateName";
      id: string;
      result: undefined;
      data: { id: string; name: string };
    }
  | {
      action: "group.updateDescription";
      id: string;
      result: undefined;
      data: { id: string; description: string };
    }
  | {
      action: "group.updateImageUrl";
      id: string;
      result: undefined;
      data: { id: string; imageUrl: string };
    }
  | {
      action: "group.updateAppData";
      id: string;
      result: undefined;
      data: { id: string; appData: string };
    }
  | {
      action: "group.updatePermission";
      id: string;
      result: undefined;
      data: {
        id: string;
        permissionType: PermissionUpdateType;
        policy: PermissionPolicy;
        metadataField?: MetadataField;
      };
    }
  | {
      action: "group.permissions";
      id: string;
      result: GroupPermissions;
      data: { id: string };
    }
  | {
      action: "group.requestRemoval";
      id: string;
      result: undefined;
      data: { id: string };
    }
  | {
      action: "group.isPendingRemoval";
      id: string;
      result: boolean;
      data: { id: string };
    };

export const preferencesActionNames = [
  "preferences.inboxState",
  "preferences.getInboxStates",
  "preferences.setConsentStates",
  "preferences.getConsentState",
  "preferences.sync",
  "preferences.streamConsent",
  "preferences.streamPreferences",
] as const;

export type PreferencesActionName = (typeof preferencesActionNames)[number];

export type PreferencesAction =
  | {
      action: "preferences.inboxState";
      id: string;
      result: InboxState;
      data: { refreshFromNetwork: boolean };
    }
  | {
      action: "preferences.getInboxStates";
      id: string;
      result: InboxState[];
      data: { inboxIds: string[]; refreshFromNetwork: boolean };
    }
  | {
      action: "preferences.setConsentStates";
      id: string;
      result: undefined;
      data: { records: Consent[] };
    }
  | {
      action: "preferences.getConsentState";
      id: string;
      result: ConsentState;
      data: { entityType: ConsentEntityType; entity: string };
    }
  | {
      action: "preferences.sync";
      id: string;
      result: GroupSyncSummary;
      data: undefined;
    }
  | {
      action: "preferences.streamConsent";
      id: string;
      result: undefined;
      data: { streamId: string };
    }
  | {
      action: "preferences.streamPreferences";
      id: string;
      result: undefined;
      data: { streamId: string };
    };

export const debugInformationActionNames = [
  "debugInformation.apiStatistics",
  "debugInformation.apiIdentityStatistics",
  "debugInformation.apiAggregateStatistics",
  "debugInformation.clearAllStatistics",
] as const;

export type DebugInformationActionName =
  (typeof debugInformationActionNames)[number];

export type DebugInformationAction =
  | {
      action: "debugInformation.apiStatistics";
      id: string;
      result: Record<string, unknown>;
      data: undefined;
    }
  | {
      action: "debugInformation.apiIdentityStatistics";
      id: string;
      result: Record<string, unknown>;
      data: undefined;
    }
  | {
      action: "debugInformation.apiAggregateStatistics";
      id: string;
      result: string;
      data: undefined;
    }
  | {
      action: "debugInformation.clearAllStatistics";
      id: string;
      result: undefined;
      data: undefined;
    };

export const dmActionNames = ["dm.peerInboxId", "dm.duplicateDms"] as const;

export type DmActionName = (typeof dmActionNames)[number];

export type DmAction =
  | {
      action: "dm.peerInboxId";
      id: string;
      result: string;
      data: { id: string };
    }
  | {
      action: "dm.duplicateDms";
      id: string;
      result: SafeConversation[];
      data: { id: string };
    };

export type BrowserWorkerAction =
  | ClientAction
  | ConversationAction
  | ConversationsAction
  | GroupAction
  | PreferencesAction
  | DebugInformationAction
  | DmAction
  | EndStreamAction;
