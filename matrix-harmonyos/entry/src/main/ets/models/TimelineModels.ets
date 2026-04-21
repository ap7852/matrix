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
  senderAvatarUrl?: string;
  content: MessageContent;
  timestamp: string;
  isOwn: boolean;
  sendState: SendState;
  inReplyTo?: ReplyPreview;
}

/**
 * 回复引用预览
 */
export interface ReplyPreview {
  eventId: string;
  senderId: string;
  senderName?: string;
  contentBody: string;
}

/**
 * 消息内容类型
 */
export interface TextContent {
  type: 'text';
  body: string;
}

/**
 * 加密文件元数据 (用于 E2EE 图片)
 */
export interface EncryptedFileData {
  key: string;
  iv: string;
  hashes?: string;
}

export interface ImageContent {
  type: 'image';
  mxcUrl: string;
  encryptedFile?: EncryptedFileData;
  body: string;
  filename?: string;
  width?: number;
  height?: number;
  mimetype?: string;
  thumbnailUrl?: string;
  localPath?: string;  // 用于发送本地图片 (上传前)
}

export interface VideoContent {
  type: 'video';
  mxcUrl: string;
  encryptedFile?: EncryptedFileData;
  body: string;
  filename?: string;
  width?: number;
  height?: number;
  duration?: number;
  mimetype?: string;
  thumbnailUrl?: string;
}

export interface FileContent {
  type: 'file';
  mxcUrl: string;
  encryptedFile?: EncryptedFileData;
  body: string;
  filename?: string;
  mimetype?: string;
  size?: number;
}

export interface AudioContent {
  type: 'audio';
  mxcUrl: string;
  encryptedFile?: EncryptedFileData;
  body: string;
  filename?: string;
  duration?: number;
  mimetype?: string;
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
  | VideoContent
  | FileContent
  | AudioContent
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