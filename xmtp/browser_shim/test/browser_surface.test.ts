import { describe, expect, it } from "vitest";
import {
  type SafeConversation,
} from "../src/contracts";
import { ApiUrls, HistorySyncUrls } from "../src/constants";
import { WorkerClient } from "../src/WorkerClient";
import { WorkerConversation } from "../src/WorkerConversation";
import { WorkerConversations } from "../src/WorkerConversations";
import { WorkerDebugInformation } from "../src/WorkerDebugInformation";
import { WorkerPreferences } from "../src/WorkerPreferences";
import {
  isActions,
  isAttachment,
  isGroupUpdated,
  isIntent,
  isLeaveRequest,
  isMarkdown,
  isMultiRemoteAttachment,
  isReadReceipt,
  isReaction,
  isRemoteAttachment,
  isReply,
  isText,
  isTextReply,
  isTransactionReference,
  isWalletSendCalls,
} from "../src/messages";

class FakeBridge {
  calls: Array<{ action: string; data?: unknown }> = [];
  responses = new Map<string, unknown>();
  streams = new Map<string, (error: Error | null, value: unknown) => void>();

  async action(action: string, data?: unknown) {
    this.calls.push({ action, data });
    return this.responses.get(action);
  }

  handleStreamMessage(
    streamId: string,
    callback: (error: Error | null, value: unknown) => void,
  ) {
    this.streams.set(streamId, callback);
    return async () => {
      this.calls.push({ action: "endStream", data: { streamId } });
      this.streams.delete(streamId);
    };
  }

  emit(streamId: string, value: unknown) {
    this.streams.get(streamId)?.(null, value);
  }
}

const conversation = (overrides: Partial<SafeConversation> = {}): SafeConversation => ({
  id: "conversation-1",
  name: "Alpha",
  imageUrl: "https://example.com/image.png",
  description: "Example conversation",
  appData: "app-data",
  permissions: { policyType: "allow", policySet: {} },
  addedByInboxId: "inbox-1",
  metadata: { conversationType: "group" },
  admins: ["inbox-1"],
  superAdmins: ["inbox-1"],
  createdAtNs: 123n,
  ...overrides,
});

describe("browser surface", () => {
  it("keeps the browser constants and message helpers explicit", () => {
    expect(ApiUrls).toEqual({
      local: "http://localhost:5557",
      dev: "https://api.dev.xmtp.network:5558",
      production: "https://api.production.xmtp.network:5558",
    });
    expect(HistorySyncUrls.mainnet).toBe(
      "https://message-history.production.ephemera.network",
    );

    expect(
      isText({
        contentType: { authorityId: "xmtp.org", typeId: "text" },
        content: "hello",
      }),
    ).toBe(true);
    expect(
      isTextReply({
        contentType: { authorityId: "xmtp.org", typeId: "reply" },
        content: { content: "reply" },
      }),
    ).toBe(true);
    expect(
      isReaction({
        contentType: { authorityId: "xmtp.org", typeId: "reaction" },
      }),
    ).toBe(true);
    expect(
      isRemoteAttachment({
        contentType: { authorityId: "xmtp.org", typeId: "remoteStaticAttachment" },
      }),
    ).toBe(true);
    expect(
      isAttachment({
        contentType: { authorityId: "xmtp.org", typeId: "attachment" },
      }),
    ).toBe(true);
    expect(
      isMultiRemoteAttachment({
        contentType: { authorityId: "xmtp.org", typeId: "multiRemoteStaticAttachment" },
      }),
    ).toBe(true);
    expect(
      isTransactionReference({
        contentType: { authorityId: "xmtp.org", typeId: "transactionReference" },
      }),
    ).toBe(true);
    expect(
      isGroupUpdated({
        contentType: { authorityId: "xmtp.org", typeId: "group_updated" },
      }),
    ).toBe(true);
    expect(
      isReadReceipt({
        contentType: { authorityId: "xmtp.org", typeId: "readReceipt" },
      }),
    ).toBe(true);
    expect(
      isLeaveRequest({
        contentType: { authorityId: "xmtp.org", typeId: "leave_request" },
      }),
    ).toBe(true);
    expect(
      isWalletSendCalls({
        contentType: { authorityId: "xmtp.org", typeId: "walletSendCalls" },
      }),
    ).toBe(true);
    expect(
      isIntent({
        contentType: { authorityId: "coinbase.com", typeId: "intent" },
      }),
    ).toBe(true);
    expect(
      isActions({
        contentType: { authorityId: "coinbase.com", typeId: "actions" },
      }),
    ).toBe(true);
    expect(
      isMarkdown({
        contentType: { authorityId: "xmtp.org", typeId: "markdown" },
      }),
    ).toBe(true);
    expect(
      isReply({
        contentType: { authorityId: "xmtp.org", typeId: "reply" },
      }),
    ).toBe(true);
  });

  it("forwards client actions through the worker-facing client wrapper", async () => {
    const bridge = new FakeBridge();
    bridge.responses.set("client.init", {
      appVersion: "1.2.3",
      accountIdentifier: { identifier: "alice" },
      env: "dev",
      inboxId: "inbox-1",
      installationId: "install-1",
      installationIdBytes: new Uint8Array([1, 2, 3]),
      libxmtpVersion: "0.1.0",
    });
    bridge.responses.set("client.isRegistered", true);
    bridge.responses.set("client.canMessage", new Map([["alice", true]]));
    bridge.responses.set(
      "client.fetchKeyPackageStatuses",
      new Map([["install-1", "active"]]),
    );
    bridge.responses.set("client.syncAllDeviceSyncGroups", { synced: true });

    const client = await WorkerClient.create(
      bridge as any,
      { identifier: "alice" } as any,
      { env: "dev", appVersion: "1.2.3" },
    );

    expect(client.appVersion).toBe("1.2.3");
    expect(client.accountIdentifier).toEqual({ identifier: "alice" });
    expect(client.env).toBe("dev");
    expect(client.inboxId).toBe("inbox-1");
    expect(client.installationId).toBe("install-1");
    expect(client.installationIdBytes).toEqual(new Uint8Array([1, 2, 3]));
    expect(client.conversations).toBeInstanceOf(WorkerConversations);
    expect(client.preferences).toBeInstanceOf(WorkerPreferences);
    expect(client.debugInformation).toBeInstanceOf(WorkerDebugInformation);

    await client.isRegistered;
    await client.canMessage([{ identifier: "alice" }]);
    await client.fetchKeyPackageStatuses(["install-1"]);
    await client.syncAllDeviceSyncGroups();
    await client.createInboxSignatureText("sig-1");
    await client.addAccountSignatureText({ identifier: "bob" }, "sig-2");

    expect(bridge.calls.map((call) => call.action)).toEqual([
      "client.init",
      "client.isRegistered",
      "client.canMessage",
      "client.fetchKeyPackageStatuses",
      "client.syncAllDeviceSyncGroups",
      "client.createInboxSignatureText",
      "client.addAccountSignatureText",
    ]);
  });

  it("forwards conversation actions and stream cleanup through the thin wrapper", async () => {
    const bridge = new FakeBridge();
    bridge.responses.set("conversation.sync", conversation({ name: "Synced" }));
    bridge.responses.set("conversation.lastMessage", { id: "message-1" });
    bridge.responses.set("conversation.isActive", true);
    bridge.responses.set("conversation.members", [{ inboxId: "inbox-1" }]);
    bridge.responses.set("conversation.countMessages", 2n);
    bridge.responses.set("conversation.messages", [{ id: "message-1" }]);
    bridge.responses.set("group.listAdmins", ["inbox-1"]);
    bridge.responses.set("group.listSuperAdmins", ["inbox-1"]);
    bridge.responses.set("group.permissions", { policyType: "allow", policySet: {} });
    bridge.responses.set("conversation.consentState", "allowed");
    bridge.responses.set(
      "conversation.messageDisappearingSettings",
      { fromNs: 1n, inNs: 2n },
    );
    bridge.responses.set("conversation.isMessageDisappearingEnabled", true);
    bridge.responses.set("conversation.pausedForVersion", undefined);
    bridge.responses.set("conversation.hmacKeys", new Map([["key", []]]));
    bridge.responses.set("conversation.debugInfo", { ok: true });
    bridge.responses.set("conversation.lastReadTimes", new Map([["inbox-1", 9n]]));
    bridge.responses.set("dm.peerInboxId", "peer-1");
    bridge.responses.set("dm.duplicateDms", [conversation({ id: "duplicate-1" })]);

    const workerConversation = new WorkerConversation(bridge as any, conversation());

    expect(workerConversation.id).toBe("conversation-1");
    expect(workerConversation.name).toBe("Alpha");
    expect(workerConversation.createdAt).toBeInstanceOf(Date);
    await expect(workerConversation.isActive).resolves.toBe(true);
    await expect(workerConversation.dmPeerInboxId()).resolves.toBe("peer-1");
    await workerConversation.sync();
    await workerConversation.updateName("Beta");
    await workerConversation.sendText("hello");
    await workerConversation.messages();
    await workerConversation.countMessages();
    await workerConversation.listAdmins();
    await workerConversation.listSuperAdmins();
    await workerConversation.permissions();
    await workerConversation.consentState();
    await workerConversation.messageDisappearingSettings();
    await workerConversation.updateMessageDisappearingSettings(1n, 2n);
    await workerConversation.removeMessageDisappearingSettings();
    await workerConversation.isMessageDisappearingEnabled();
    await workerConversation.pausedForVersion();
    await workerConversation.hmacKeys();
    await workerConversation.debugInfo();
    await workerConversation.lastReadTimes();

    const stream = await workerConversation.stream();
    const next = stream.next();
    const streamRequest = bridge.calls.find(
      (call) => call.action === "conversation.stream",
    );
    const streamId = (streamRequest?.data as { streamId?: string } | undefined)?.streamId;
    expect(streamId).toBeDefined();
    bridge.emit(streamId as string, { id: "message-2" });
    const streamResult = await next;
    expect(streamResult).toEqual({
      done: false,
      value: { id: "message-2" },
    });
    await stream.end();
    expect(bridge.calls.map((call) => call.action)).toContain("endStream");

    await workerConversation.duplicateDms();
    await workerConversation.requestRemoval();
    await workerConversation.isPendingRemoval();
  });

  it("forwards conversations, preferences, and debug actions through the thin wrappers", async () => {
    const bridge = new FakeBridge();
    bridge.responses.set("conversations.getConversationById", conversation());
    bridge.responses.set("conversations.getMessageById", { id: "message-1" });
    bridge.responses.set("conversations.getDmByInboxId", conversation({ id: "dm-1" }));
    bridge.responses.set(
      "conversations.list",
      [conversation(), conversation({ id: "conversation-2" })],
    );
    bridge.responses.set("conversations.listGroups", [conversation()]);
    bridge.responses.set("conversations.listDms", [conversation({ id: "dm-1" })]);
    bridge.responses.set(
      "conversations.createGroupOptimistic",
      conversation({ id: "group-optimistic" }),
    );
    bridge.responses.set(
      "conversations.createGroupWithIdentifiers",
      conversation({ id: "group-identifiers" }),
    );
    bridge.responses.set("conversations.createGroup", conversation({ id: "group-inboxes" }));
    bridge.responses.set(
      "conversations.createDmWithIdentifier",
      conversation({ id: "dm-identifier" }),
    );
    bridge.responses.set("conversations.createDm", conversation({ id: "dm-inbox" }));
    bridge.responses.set("conversations.hmacKeys", new Map([["key", []]]));
    bridge.responses.set("conversations.streamAllGroupMessages", undefined);
    bridge.responses.set("conversations.streamAllDmMessages", undefined);
    bridge.responses.set("conversations.streamDeletedMessages", undefined);
    bridge.responses.set("preferences.sync", { synced: true });
    bridge.responses.set("preferences.inboxState", { inbox: "state" });
    bridge.responses.set("preferences.getInboxStates", [{ inbox: "state" }]);
    bridge.responses.set("preferences.setConsentStates", undefined);
    bridge.responses.set("preferences.getConsentState", "allowed");
    bridge.responses.set("debugInformation.apiStatistics", { calls: 1 });
    bridge.responses.set("debugInformation.apiIdentityStatistics", { calls: 2 });
    bridge.responses.set("debugInformation.apiAggregateStatistics", "aggregate");
    bridge.responses.set("debugInformation.clearAllStatistics", undefined);

    const conversations = new WorkerConversations(bridge as any);
    const preferences = new WorkerPreferences(bridge as any);
    const debug = new WorkerDebugInformation(bridge as any);

    expect((await conversations.getConversationById("conversation-1"))?.id).toBe("conversation-1");
    expect((await conversations.getMessageById("message-1"))?.id).toBe("message-1");
    expect((await conversations.getDmByInboxId("dm-1"))?.id).toBe("dm-1");
    expect((await conversations.list())?.[0]?.id).toBe("conversation-1");
    expect((await conversations.listGroups())?.[0]?.id).toBe("conversation-1");
    expect((await conversations.listDms())?.[0]?.id).toBe("dm-1");
    expect((await conversations.createGroupOptimistic())?.id).toBe("group-optimistic");
    expect(
      (await conversations.createGroupWithIdentifiers([{ identifier: "bob" }]))?.id,
    ).toBe("group-identifiers");
    expect((await conversations.createGroup(["inbox-1"]))?.id).toBe("group-inboxes");
    expect((await conversations.createDmWithIdentifier({ identifier: "bob" }))?.id).toBe("dm-identifier");
    expect((await conversations.createDm("dm-1"))?.id).toBe("dm-inbox");
    await conversations.sync();
    await conversations.syncAll(["allowed"]);
    await conversations.hmacKeys();

    const groupMessageStream = await conversations.streamAllGroupMessages();
    const groupMessageNext = groupMessageStream.next();
    const groupMessageStreamRequest = bridge.calls.find(
      (call) => call.action === "conversations.streamAllGroupMessages",
    );
    const groupMessageStreamId = (
      groupMessageStreamRequest?.data as { streamId?: string } | undefined
    )?.streamId;
    bridge.emit(groupMessageStreamId as string, { id: "group-message-1" });
    await expect(groupMessageNext).resolves.toEqual({
      done: false,
      value: { id: "group-message-1" },
    });
    await groupMessageStream.end();

    const dmMessageStream = await conversations.streamAllDmMessages();
    const dmMessageNext = dmMessageStream.next();
    const dmMessageStreamRequest = bridge.calls.find(
      (call) => call.action === "conversations.streamAllDmMessages",
    );
    const dmMessageStreamId = (
      dmMessageStreamRequest?.data as { streamId?: string } | undefined
    )?.streamId;
    bridge.emit(dmMessageStreamId as string, { id: "dm-message-1" });
    await expect(dmMessageNext).resolves.toEqual({
      done: false,
      value: { id: "dm-message-1" },
    });
    await dmMessageStream.end();

    const deletedMessageStream = await conversations.streamDeletedMessages();
    const deletedMessageNext = deletedMessageStream.next();
    const deletedMessageStreamRequest = bridge.calls.find(
      (call) => call.action === "conversations.streamDeletedMessages",
    );
    const deletedMessageStreamId = (
      deletedMessageStreamRequest?.data as { streamId?: string } | undefined
    )?.streamId;
    bridge.emit(deletedMessageStreamId as string, { id: "deleted-message-1" });
    await expect(deletedMessageNext).resolves.toEqual({
      done: false,
      value: { id: "deleted-message-1" },
    });
    await deletedMessageStream.end();

    const conversationStream = await conversations.stream({ conversationType: "group" });
    const conversationNext = conversationStream.next();
    const conversationStreamRequest = bridge.calls.find(
      (call) => call.action === "conversations.stream",
    );
    const conversationStreamId = (
      conversationStreamRequest?.data as { streamId?: string } | undefined
    )?.streamId;
    bridge.emit(conversationStreamId as string, conversation({ id: "conversation-3" }));
    const conversationResult = await conversationNext;
    expect(conversationResult.done).toBe(false);
    expect(conversationResult.value).toMatchObject({ id: "conversation-3" });
    await conversationStream.end();

    const consentStream = await preferences.streamConsent();
    const consentNext = consentStream.next();
    const consentStreamRequest = bridge.calls.find(
      (call) => call.action === "preferences.streamConsent",
    );
    const consentStreamId = (
      consentStreamRequest?.data as { streamId?: string } | undefined
    )?.streamId;
    bridge.emit(consentStreamId as string, [{ id: "consent-2" }]);
    await expect(consentNext).resolves.toEqual({
      done: false,
      value: [{ id: "consent-2" }],
    });
    await consentStream.end();

    const preferenceStream = await preferences.streamPreferences();
    const preferenceNext = preferenceStream.next();
    const preferenceStreamRequest = bridge.calls.find(
      (call) => call.action === "preferences.streamPreferences",
    );
    const preferenceStreamId = (
      preferenceStreamRequest?.data as { streamId?: string } | undefined
    )?.streamId;
    bridge.emit(preferenceStreamId as string, [{ kind: "hmac_key", consent: null }]);
    await expect(preferenceNext).resolves.toEqual({
      done: false,
      value: [{ kind: "hmac_key", consent: null }],
    });
    await preferenceStream.end();

    await preferences.sync();
    await preferences.inboxState(true);
    await preferences.getInboxStates(["inbox-1"], true);
    await preferences.setConsentStates([{ entity: "inbox-1", state: "allowed" }]);
    await preferences.getConsentState("inbox_id", "value");

    await debug.apiStatistics();
    await debug.apiIdentityStatistics();
    await debug.apiAggregateStatistics();
    await debug.clearAllStatistics();

    expect(bridge.calls.some((call) => call.action === "endStream")).toBe(true);
    expect(bridge.calls.filter((call) => call.action === "endStream")).toHaveLength(6);
  });
});
