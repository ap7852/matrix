/**
 * Media 服务 - 图片上传下载
 */

import { getBridge } from './MatrixBridge';
import { ImageContent, EncryptedFileData } from '../models/TimelineModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0006;
const TAG = 'MediaService';

export class MediaService {
  // Base64 缓存 (内存缓存，避免重复下载)
  private static cache: Map<string, string> = new Map();

  /**
   * 下载图片并返回 Base64 数据
   *
   * @param content 图片内容信息
   * @returns Base64 编码的图片数据
   */
  static async downloadImage(content: ImageContent): Promise<string> {
    // 检查缓存
    const cacheKey = content.mxcUrl;
    if (MediaService.cache.has(cacheKey)) {
      hilog.debug(DOMAIN, TAG, 'Image cached: %{public}s', cacheKey);
      return MediaService.cache.get(cacheKey)!;
    }

    hilog.info(DOMAIN, TAG, 'Downloading image: %{public}s', cacheKey);

    // 准备加密文件 JSON (如果有)
    const encryptedFileJson = content.encryptedFile
      ? JSON.stringify(content.encryptedFile)
      : undefined;

    // 调用 NAPI 下载
    const bridge = getBridge();
    const base64Data: string = await bridge.napiDownloadImage(content.mxcUrl, encryptedFileJson) as string;

    // 缓存结果
    MediaService.cache.set(cacheKey, base64Data);
    hilog.info(DOMAIN, TAG, 'Image downloaded and cached, size: %{public}d', base64Data.length);

    return base64Data;
  }

  /**
   * 上传图片并发送到房间
   *
   * @param roomId 房间 ID
   * @param filename 文件名
   * @param mimetype MIME 类型
   * @param dataBase64 Base64 编码的图片数据
   * @returns 发送成功的 event_id
   */
  static async sendImage(
    roomId: string,
    filename: string,
    mimetype: string,
    dataBase64: string
  ): Promise<string> {
    hilog.info(DOMAIN, TAG, 'Sending image to room: %{public}s, filename: %{public}s', roomId, filename);

    const bridge = getBridge();
    const eventId: string = await bridge.napiSendImage(roomId, filename, mimetype, dataBase64) as string;

    hilog.info(DOMAIN, TAG, 'Image sent, event_id: %{public}s', eventId);
    return eventId;
  }

  /**
   * 清除缓存
   */
  static clearCache(): void {
    MediaService.cache.clear();
    hilog.info(DOMAIN, TAG, 'Cache cleared');
  }
}