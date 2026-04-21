/**
 * Element X HarmonyOS - Rust NAPI Bridge Type Declarations
 */

export interface MatrixBridge {
  // === 测试函数 ===
  hello(): string;
  verifyRingCompile(): string;
  add(a: number, b: number): number;
  helloAsync(name: string): Promise<string>;
  init(): void;
  testError(): string;

  // === 认证函数 ===
  napiLoginPassword(
    homeserver: string,
    username: string,
    password: string,
    dataDir: string
  ): Promise<string>;
  napiHasSession(): boolean;
  napiRestoreSession(dataDir: string): Promise<string>;
  napiLogout(dataDir: string): Promise<void>;
  napiClearState(dataDir: string): Promise<void>;

  // === 房间列表函数 ===
  napiInitRoomListService(): Promise<void>;
  napiSubscribeRoomList(callback: (json: string) => void): Promise<void>;
  napiStopRoomListSync(): Promise<void>;

  // === 房间函数 ===
  napiGetRoomDetails(roomId: string): Promise<string>;
  napiGetRoomMembers(roomId: string): Promise<string>;

  // === Timeline 函数 ===
  napiInitTimeline(roomId: string): Promise<void>;
  napiSubscribeTimeline(roomId: string, callback: (json: string) => void): void;
  napiSendText(roomId: string, text: string, replyTo?: string): Promise<void>;
  napiPaginateBackwards(roomId: string): Promise<boolean>;
  napiSendReadReceipt(roomId: string, eventId: string): Promise<void>;
  napiEditMessage(roomId: string, eventId: string, newText: string): Promise<void>;
  napiRedactMessage(roomId: string, eventId: string, reason?: string): Promise<void>;
  napiReplyToMessage(roomId: string, eventId: string, text: string): Promise<void>;
  napiToggleReaction(roomId: string, eventId: string, key: string): Promise<void>;

  // === 媒体函数 ===
  napiDownloadImage(mxcUrl: string, encryptedFileJson?: string): Promise<string>;
  napiSendImage(roomId: string, filename: string, mimetype: string, dataBase64: string): Promise<string>;

  // === 加密同步函数 ===
  napiInitSyncService(): Promise<void>;
  napiStartSync(): Promise<void>;
  napiStopSync(): Promise<void>;
}

declare const matrixBridge: MatrixBridge;
export default matrixBridge;