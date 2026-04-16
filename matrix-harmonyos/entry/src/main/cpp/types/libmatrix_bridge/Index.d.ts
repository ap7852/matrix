/**
 * Element X HarmonyOS - Rust NAPI Bridge Type Declarations
 *
 * 由 ohos-rs 自动生成，或手动维护
 */

export interface MatrixBridge {
  /**
   * Hello World 测试函数
   * 返回欢迎消息验证 NAPI 桥接成功
   */
  hello(): string;

  /**
   * 验证 ring crate 编译成功
   * 返回 SHA256 哈希值前 8 字节（十六进制字符串）
   */
  verifyRingCompile(): string;

  /**
   * 加法运算测试
   * 替代原有 C++ NAPI add 函数
   */
  add(a: number, b: number): number;

  /**
   * 异步 Hello World
   * 返回 Promise，验证 tokio 运行时工作正常
   */
  helloAsync(name: string): Promise<string>;

  /**
   * 初始化 NAPI 运行时
   * 初始化 tokio 单例运行时
   */
  init(): void;

  /**
   * 测试错误处理
   * 返回结构化错误用于验证错误码系统
   */
  testError(): string;
}

declare const matrixBridge: MatrixBridge;
export default matrixBridge;