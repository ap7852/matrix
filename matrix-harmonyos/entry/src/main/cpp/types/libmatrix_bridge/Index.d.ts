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

  // === 房间列表函数 ===
  napiStartRoomListSync(): Promise<string>;
}

declare const matrixBridge: MatrixBridge;
export default matrixBridge;