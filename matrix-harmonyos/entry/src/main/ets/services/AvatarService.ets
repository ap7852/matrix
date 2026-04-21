/**
 * Avatar 服务 - 头像下载缓存
 */

import { getBridge } from './MatrixBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0006;
const TAG = 'AvatarService';

export class AvatarService {
  // Base64 缓存 (内存缓存，避免重复下载)
  private static cache: Map<string, string> = new Map();

  /**
   * 获取头像并返回 Base64 数据
   *
   * @param mxcUrl mxc:// URL
   * @returns Base64 编码的头像数据
   */
  static async getAvatar(mxcUrl: string): Promise<string> {
    // 检查缓存
    if (AvatarService.cache.has(mxcUrl)) {
      return AvatarService.cache.get(mxcUrl)!;
    }

    hilog.info(DOMAIN, TAG, 'Downloading avatar: %{public}s', mxcUrl);

    // 调用 NAPI 下载 (使用与图片下载相同的函数)
    const bridge = getBridge();
    const base64Data: string = await bridge.napiDownloadImage(mxcUrl, undefined) as string;

    // 缓存结果
    AvatarService.cache.set(mxcUrl, base64Data);
    hilog.info(DOMAIN, TAG, 'Avatar downloaded and cached');

    return base64Data;
  }

  /**
   * 清除缓存
   */
  static clearCache(): void {
    AvatarService.cache.clear();
    hilog.info(DOMAIN, TAG, 'Avatar cache cleared');
  }
}