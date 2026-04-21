/**
 * Media 服务 - 图片上传下载
 */

import { getBridge } from './MatrixBridge';
import { ImageContent, EncryptedFileData } from '../models/TimelineModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0006;
const TAG = 'MediaService';

// 最大并发下载数
const MAX_CONCURRENT_DOWNLOADS = 3;
// 单次下载超时时间 (毫秒)
const DOWNLOAD_TIMEOUT_MS = 30000;
// 等待队列超时时间 (毫秒)
const QUEUE_WAIT_TIMEOUT_MS = 60000;

// 下载队列项接口
interface DownloadQueueItem {
  content: ImageContent;
  resolve: (value: string) => void;
  reject: (error: Error) => void;
  startTime: number;
}

export class MediaService {
  // Base64 缓存 (内存缓存，避免重复下载)
  private static cache: Map<string, string> = new Map();

  // 正在下载中的 Promise (防止重复请求同一图片)
  private static pendingDownloads: Map<string, Promise<string>> = new Map();

  // 下载队列 (等待执行的下载)
  private static downloadQueue: DownloadQueueItem[] = [];

  // 当前活跃下载计数
  private static activeDownloads: number = 0;

  /**
   * 下载图片并返回 Base64 数据
   *
   * @param content 图片内容信息
   * @returns Base64 编码的图片数据
   */
  static async downloadImage(content: ImageContent): Promise<string> {
    const cacheKey = content.mxcUrl;

    // 1. 检查缓存
    if (MediaService.cache.has(cacheKey)) {
      hilog.debug(DOMAIN, TAG, 'Image cached: %{public}s', cacheKey);
      return MediaService.cache.get(cacheKey)!;
    }

    // 2. 检查是否正在下载中 (避免重复请求)
    if (MediaService.pendingDownloads.has(cacheKey)) {
      hilog.info(DOMAIN, TAG, 'Waiting for pending download: %{public}s', cacheKey);
      // 等待已有的下载完成，带超时保护
      return MediaService.waitForPendingDownload(cacheKey);
    }

    // 3. 创建下载 Promise 并加入队列
    hilog.info(DOMAIN, TAG, 'Queuing download: %{public}s', cacheKey);
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      const item: DownloadQueueItem = {
        content: content,
        resolve: resolve,
        reject: reject,
        startTime: Date.now()
      };
      MediaService.downloadQueue.push(item);
      MediaService.processQueue();
    });
  }

  /**
   * 等待已有的下载完成 (带超时)
   */
  private static async waitForPendingDownload(cacheKey: string): Promise<string> {
    const pendingPromise = MediaService.pendingDownloads.get(cacheKey);
    if (!pendingPromise) {
      throw new Error('No pending download found');
    }

    // 使用超时包装等待
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      const timeoutId = setTimeout(() => {
        reject(new Error('等待下载超时'));
      }, DOWNLOAD_TIMEOUT_MS);

      pendingPromise
        .then((result: string) => {
          clearTimeout(timeoutId);
          resolve(result);
        })
        .catch((err: Error) => {
          clearTimeout(timeoutId);
          reject(err);
        });
    });
  }

  /**
   * 处理下载队列
   */
  private static processQueue(): void {
    // 检查队列超时的请求
    const now = Date.now();
    const validItems: DownloadQueueItem[] = [];

    for (const item of MediaService.downloadQueue) {
      if (now - item.startTime > QUEUE_WAIT_TIMEOUT_MS) {
        hilog.warn(DOMAIN, TAG, 'Queue wait timeout for: %{public}s', item.content.mxcUrl);
        item.reject(new Error('队列等待超时'));
      } else {
        validItems.push(item);
      }
    }
    MediaService.downloadQueue = validItems;

    // 如果有空闲槽位，启动新的下载
    while (MediaService.activeDownloads < MAX_CONCURRENT_DOWNLOADS && MediaService.downloadQueue.length > 0) {
      const item = MediaService.downloadQueue.shift();
      if (item) {
        MediaService.startDownload(item);
      }
    }
  }

  /**
   * 启动下载
   */
  private static startDownload(item: DownloadQueueItem): void {
    const cacheKey = item.content.mxcUrl;
    MediaService.activeDownloads++;
    hilog.info(DOMAIN, TAG, 'Starting download %{public}s (active: %{public}d, queue: %{public}d)',
      cacheKey, MediaService.activeDownloads, MediaService.downloadQueue.length);

    // 创建带超时的下载 Promise
    const downloadPromise = MediaService.doDownloadWithTimeout(item.content);

    MediaService.pendingDownloads.set(cacheKey, downloadPromise);

    downloadPromise
      .then((result: string) => {
        MediaService.cache.set(cacheKey, result);
        hilog.info(DOMAIN, TAG, 'Download complete %{public}s, size: %{public}d', cacheKey, result.length);
        item.resolve(result);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Download failed %{public}s: %{public}s', cacheKey, err.message);
        item.reject(err);
      })
      .finally(() => {
        MediaService.pendingDownloads.delete(cacheKey);
        MediaService.activeDownloads--;
        hilog.info(DOMAIN, TAG, 'Download slot released %{public}s (active: %{public}d)', cacheKey, MediaService.activeDownloads);
        // 处理队列中的下一个请求
        MediaService.processQueue();
      });
  }

  /**
   * 执行下载 (带超时)
   */
  private static async doDownloadWithTimeout(content: ImageContent): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      const timeoutId = setTimeout(() => {
        reject(new Error('下载超时 (30秒)'));
      }, DOWNLOAD_TIMEOUT_MS);

      MediaService.doDownload(content)
        .then((result: string) => {
          clearTimeout(timeoutId);
          resolve(result);
        })
        .catch((err: Error) => {
          clearTimeout(timeoutId);
          reject(err);
        });
    });
  }

  /**
   * 实际执行下载 (内部方法)
   */
  private static async doDownload(content: ImageContent): Promise<string> {
    // 准备加密文件 JSON (如果有)
    const encryptedFileJson = content.encryptedFile
      ? JSON.stringify(content.encryptedFile)
      : undefined;

    // 调用 NAPI 下载
    const bridge = getBridge();
    const base64Data: string = await bridge.napiDownloadImage(content.mxcUrl, encryptedFileJson) as string;

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