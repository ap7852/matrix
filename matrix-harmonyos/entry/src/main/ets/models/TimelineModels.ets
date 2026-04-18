/**
 * Timeline 数据模型
 *
 * 对应 Rust sdk-wrapper/src/timeline.rs 中的数据结构
 */

/**
 * 时间线消息数据
 */
export interface TimelineMessage {
  eventId?: string;
  senderId: string;
  senderName: string;
  content: MessageContent;
  timestamp: string;
  isOwn: boolean;
  sendState: SendState;
}

/**
 * 消息内容类型
 */
export interface TextContent {
  type: 'text';
  body: string;
}

export interface ImageContent {
  type: 'image';
  mxcUrl: string;
}

export interface UnableToDecryptContent {
  type: 'unableToDecrypt';
  reason: string;
}

export interface RedactedContent {
  type: 'redacted';
}

export interface UnsupportedContent {
  type: 'unsupported';
}

export type MessageContent =
  | TextContent
  | ImageContent
  | UnableToDecryptContent
  | RedactedContent
  | UnsupportedContent;

/**
 * 发送状态
 */
export type SendState = 'sending' | 'sent' | 'failed';

/**
 * 时间线更新消息
 */
export interface TimelineResetUpdate {
  type: 'reset';
  items: TimelineMessage[];
}

export interface TimelineAppendUpdate {
  type: 'append';
  items: TimelineMessage[];
}

export interface TimelineInsertUpdate {
  type: 'insert';
  index: number;
  item: TimelineMessage;
}

export interface TimelineUpdateUpdate {
  type: 'update';
  index: number;
  item: TimelineMessage;
}

export interface TimelineRemoveUpdate {
  type: 'remove';
  index: number;
}

export type TimelineUpdate =
  | TimelineResetUpdate
  | TimelineAppendUpdate
  | TimelineInsertUpdate
  | TimelineUpdateUpdate
  | TimelineRemoveUpdate;