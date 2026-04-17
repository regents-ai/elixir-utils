export type DecodedMessageLike<Content = unknown> = {
  contentType: {
    authorityId: string;
    typeId: string;
  };
  content?: Content;
};

export const isReaction = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "reaction";

export const isReply = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "reply";

export const isTextReply = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ content: string }> =>
  isReply(message) && typeof (message.content as { content?: unknown } | undefined)?.content === "string";

export const isText = (message: DecodedMessageLike): message is DecodedMessageLike<string> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "text";

export const isRemoteAttachment = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "remoteStaticAttachment";

export const isAttachment = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "attachment";

export const isMultiRemoteAttachment = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "multiRemoteStaticAttachment";

export const isTransactionReference = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "transactionReference";

export const isGroupUpdated = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "group_updated";

export const isReadReceipt = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "readReceipt";

export const isLeaveRequest = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "leave_request";

export const isWalletSendCalls = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "walletSendCalls";

export const isIntent = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "coinbase.com" &&
  message.contentType.typeId === "intent";

export const isActions = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<{ [key: string]: unknown }> =>
  message.contentType.authorityId === "coinbase.com" &&
  message.contentType.typeId === "actions";

export const isMarkdown = (
  message: DecodedMessageLike,
): message is DecodedMessageLike<string> =>
  message.contentType.authorityId === "xmtp.org" &&
  message.contentType.typeId === "markdown";
