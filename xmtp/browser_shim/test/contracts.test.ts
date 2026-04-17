import { describe, expect, expectTypeOf, it } from "vitest";
import {
  clientActionNames,
  clientWorkerActionNames,
  conversationActionNames,
  conversationsActionNames,
  debugInformationActionNames,
  dmActionNames,
  groupActionNames,
  opfsActionNames,
  preferencesActionNames,
  streamActionNames,
  type BrowserWorkerAction,
  type ClientAction,
  type ClientActionName,
  type ClientWorkerAction,
  type ConversationAction,
  type ConversationsAction,
  type DebugInformationAction,
  type DmAction,
  type GroupAction,
  type OpfsAction,
  type PreferencesAction,
  type StreamAction,
} from "../src/contracts";

describe("contracts", () => {
  it("keeps the client worker action surface explicit", () => {
    expect(clientActionNames).toEqual([
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
    ]);

    expect(clientWorkerActionNames).toEqual([
      ...clientActionNames,
      "endStream",
    ]);

    expectTypeOf<ClientAction["action"]>().toEqualTypeOf<ClientActionName>();
    expectTypeOf<ClientWorkerAction["action"]>().toEqualTypeOf<
      ClientActionName | "endStream"
    >();
  });

  it("keeps the browser wrapper action surfaces explicit", () => {
    expect(conversationActionNames).toEqual([
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
    ]);

    expect(conversationsActionNames).toEqual([
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
    ]);

    expect(groupActionNames).toEqual([
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
    ]);

    expect(preferencesActionNames).toEqual([
      "preferences.inboxState",
      "preferences.getInboxStates",
      "preferences.setConsentStates",
      "preferences.getConsentState",
      "preferences.sync",
      "preferences.streamConsent",
      "preferences.streamPreferences",
    ]);

    expect(debugInformationActionNames).toEqual([
      "debugInformation.apiStatistics",
      "debugInformation.apiIdentityStatistics",
      "debugInformation.apiAggregateStatistics",
      "debugInformation.clearAllStatistics",
    ]);

    expect(dmActionNames).toEqual([
      "dm.peerInboxId",
      "dm.duplicateDms",
    ]);

    expectTypeOf<ConversationAction["action"]>().toEqualTypeOf<
      (typeof conversationActionNames)[number]
    >();
    expectTypeOf<ConversationsAction["action"]>().toEqualTypeOf<
      (typeof conversationsActionNames)[number]
    >();
    expectTypeOf<GroupAction["action"]>().toEqualTypeOf<
      (typeof groupActionNames)[number]
    >();
    expectTypeOf<PreferencesAction["action"]>().toEqualTypeOf<
      (typeof preferencesActionNames)[number]
    >();
    expectTypeOf<DebugInformationAction["action"]>().toEqualTypeOf<
      (typeof debugInformationActionNames)[number]
    >();
    expectTypeOf<DmAction["action"]>().toEqualTypeOf<
      (typeof dmActionNames)[number]
    >();
    expectTypeOf<BrowserWorkerAction["action"]>().toEqualTypeOf<
      | ClientWorkerAction["action"]
      | ConversationAction["action"]
      | ConversationsAction["action"]
      | GroupAction["action"]
      | PreferencesAction["action"]
      | DebugInformationAction["action"]
      | DmAction["action"]
    >();
  });

  it("keeps the browser stream and opfs surfaces explicit", () => {
    expect(streamActionNames).toEqual([
      "stream.message",
      "stream.conversation",
      "stream.consent",
      "stream.preferences",
      "stream.deletedMessage",
      "stream.fail",
    ]);

    expect(opfsActionNames).toEqual([
      "opfs.init",
      "opfs.listFiles",
      "opfs.fileCount",
      "opfs.poolCapacity",
      "opfs.fileExists",
      "opfs.deleteFile",
      "opfs.exportDb",
      "opfs.importDb",
      "opfs.clearAll",
    ]);

    expectTypeOf<StreamAction["action"]>().toEqualTypeOf<
      (typeof streamActionNames)[number]
    >();
    expectTypeOf<OpfsAction["action"]>().toEqualTypeOf<
      (typeof opfsActionNames)[number]
    >();
  });
});
