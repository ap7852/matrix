/**
 * Matrix Bridge - NAPI 模块加载器
 *
 * 动态加载 libmatrix_bridge.so 并初始化 tokio runtime
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import matrixBridge, { MatrixBridge } from 'libmatrix_bridge.so';

const DOMAIN = 0x0005;
const TAG = 'MatrixBridge';

let bridgeInstance: MatrixBridge | null = null;
let initError: string | null = null;

/**
 * 初始化 Matrix Bridge
 * @returns true if successful, false if failed
 */
export async function initMatrixBridge(): Promise<boolean> {
  try {
    bridgeInstance = matrixBridge;
    bridgeInstance.init();
    hilog.info(DOMAIN, TAG, 'Matrix bridge initialized');
    return true;
  } catch (err) {
    const error = err as Error;
    initError = error.message;
    hilog.error(DOMAIN, TAG, 'Failed to initialize bridge: %{public}s', error.message);
    return false;
  }
}

/**
 * 检查 Bridge 是否已初始化
 */
export function isBridgeReady(): boolean {
  return bridgeInstance !== null;
}

/**
 * 获取初始化错误信息
 */
export function getInitError(): string | null {
  return initError;
}

/**
 * 获取 Bridge 实例
 */
export function getBridge(): MatrixBridge {
  if (!bridgeInstance) {
    throw new Error(initError ?? 'Matrix bridge not initialized');
  }
  return bridgeInstance;
}