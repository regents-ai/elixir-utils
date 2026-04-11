import type {
  ArchiveMetadata,
  ArchiveOptions,
  AvailableArchiveInfo,
  BrowserWorkerAction,
  ClientOptions,
  GroupSyncSummary,
  Identifier,
  KeyPackageStatus,
  SafeSigner,
  XmtpEnv,
} from "./contracts";
import { WorkerBridge } from "./WorkerBridge";
import { WorkerConversations } from "./WorkerConversations";
import { WorkerDebugInformation } from "./WorkerDebugInformation";
import { WorkerPreferences } from "./WorkerPreferences";

export type WorkerClientInit = {
  appVersion: string;
  accountIdentifier: Identifier;
  env: XmtpEnv;
  inboxId: string;
  installationId: string;
  installationIdBytes: Uint8Array;
  libxmtpVersion: string;
};

export class WorkerClient {
  #bridge: WorkerBridge<BrowserWorkerAction>;
  #conversations?: WorkerConversations;
  #debugInformation?: WorkerDebugInformation;
  #init: WorkerClientInit;
  #preferences?: WorkerPreferences;

  constructor(bridge: WorkerBridge<BrowserWorkerAction>, init: WorkerClientInit) {
    this.#bridge = bridge;
    this.#init = init;
  }

  static async create(
    bridge: WorkerBridge<BrowserWorkerAction>,
    identifier: Identifier,
    options?: Omit<ClientOptions, "codecs">,
  ) {
    const init = await bridge.action("client.init", { identifier, options });
    return new WorkerClient(bridge, init);
  }

  get libxmtpVersion() {
    return this.#init.libxmtpVersion;
  }

  get appVersion() {
    return this.#init.appVersion;
  }

  get accountIdentifier() {
    return this.#init.accountIdentifier;
  }

  get env() {
    return this.#init.env;
  }

  get inboxId() {
    return this.#init.inboxId;
  }

  get installationId() {
    return this.#init.installationId;
  }

  get installationIdBytes() {
    return this.#init.installationIdBytes;
  }

  get conversations() {
    this.#conversations ??= new WorkerConversations(this.#bridge);
    return this.#conversations;
  }

  get debugInformation() {
    this.#debugInformation ??= new WorkerDebugInformation(this.#bridge);
    return this.#debugInformation;
  }

  get preferences() {
    this.#preferences ??= new WorkerPreferences(this.#bridge);
    return this.#preferences;
  }

  async canMessage(identifiers: Identifier[]) {
    return this.#bridge.action("client.canMessage", { identifiers });
  }

  async applySignatureRequest(signatureRequestId: string, signer: SafeSigner) {
    return this.#bridge.action("client.applySignatureRequest", {
      signatureRequestId,
      signer,
    });
  }

  async createInboxSignatureText(signatureRequestId: string) {
    return this.#bridge.action("client.createInboxSignatureText", {
      signatureRequestId,
    });
  }

  async addAccountSignatureText(
    newIdentifier: Identifier,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.addAccountSignatureText", {
      newIdentifier,
      signatureRequestId,
    });
  }

  async removeAccountSignatureText(
    identifier: Identifier,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.removeAccountSignatureText", {
      identifier,
      signatureRequestId,
    });
  }

  async revokeAllOtherInstallationsSignatureText(signatureRequestId: string) {
    return this.#bridge.action(
      "client.revokeAllOtherInstallationsSignatureText",
      { signatureRequestId },
    );
  }

  async revokeInstallationsSignatureText(
    installationIds: Uint8Array[],
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.revokeInstallationsSignatureText", {
      installationIds,
      signatureRequestId,
    });
  }

  async changeRecoveryIdentifierSignatureText(
    identifier: Identifier,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.changeRecoveryIdentifierSignatureText", {
      identifier,
      signatureRequestId,
    });
  }

  async registerIdentity(signatureRequestId: string, signer: SafeSigner) {
    return this.#bridge.action("client.registerIdentity", {
      signatureRequestId,
      signer,
    });
  }

  async addAccount(
    identifier: Identifier,
    signer: SafeSigner,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.addAccount", {
      identifier,
      signer,
      signatureRequestId,
    });
  }

  async removeAccount(
    identifier: Identifier,
    signer: SafeSigner,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.removeAccount", {
      identifier,
      signer,
      signatureRequestId,
    });
  }

  async revokeAllOtherInstallations(
    signer: SafeSigner,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.revokeAllOtherInstallations", {
      signer,
      signatureRequestId,
    });
  }

  async changeRecoveryIdentifier(
    identifier: Identifier,
    signer: SafeSigner,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.changeRecoveryIdentifier", {
      identifier,
      signer,
      signatureRequestId,
    });
  }

  async revokeInstallations(
    installationIds: Uint8Array[],
    signer: SafeSigner,
    signatureRequestId: string,
  ) {
    return this.#bridge.action("client.revokeInstallations", {
      installationIds,
      signer,
      signatureRequestId,
    });
  }

  get isRegistered() {
    return this.#bridge.action("client.isRegistered");
  }

  async getInboxIdByIdentifier(identifier: Identifier) {
    return this.#bridge.action("client.getInboxIdByIdentifier", { identifier });
  }

  signWithInstallationKey(signatureText: string) {
    return this.#bridge.action("client.signWithInstallationKey", {
      signatureText,
    });
  }

  async verifySignedWithInstallationKey(
    signatureText: string,
    signatureBytes: Uint8Array,
  ) {
    return this.#bridge.action("client.verifySignedWithInstallationKey", {
      signatureText,
      signatureBytes,
    });
  }

  async verifySignedWithPublicKey(
    signatureText: string,
    signatureBytes: Uint8Array,
    publicKey: Uint8Array,
  ) {
    return this.#bridge.action("client.verifySignedWithPublicKey", {
      signatureText,
      signatureBytes,
      publicKey,
    });
  }

  async fetchKeyPackageStatuses(installationIds: string[]) {
    return this.#bridge.action("client.fetchKeyPackageStatuses", {
      installationIds,
    });
  }

  async sendSyncRequest(options: ArchiveOptions, serverUrl: string) {
    return this.#bridge.action("client.sendSyncRequest", {
      options,
      serverUrl,
    });
  }

  async sendSyncArchive(
    options: ArchiveOptions,
    serverUrl: string,
    pin: string,
  ) {
    return this.#bridge.action("client.sendSyncArchive", {
      options,
      serverUrl,
      pin,
    });
  }

  async processSyncArchive(archivePin?: string | null) {
    return this.#bridge.action("client.processSyncArchive", { archivePin });
  }

  listAvailableArchives(daysCutoff: number) {
    return this.#bridge.action("client.listAvailableArchives", { daysCutoff });
  }

  async createArchive(opts: ArchiveOptions, key: Uint8Array) {
    return this.#bridge.action("client.createArchive", { opts, key });
  }

  async importArchive(data: Uint8Array, key: Uint8Array) {
    return this.#bridge.action("client.importArchive", { data, key });
  }

  async archiveMetadata(data: Uint8Array, key: Uint8Array) {
    return this.#bridge.action("client.archiveMetadata", { data, key });
  }

  async syncAllDeviceSyncGroups(): Promise<GroupSyncSummary> {
    return this.#bridge.action("client.syncAllDeviceSyncGroups");
  }
}
