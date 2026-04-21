/**
 * 图片消息组件
 *
 * 显示图片消息，支持自动下载和缓存
 */

import { ImageContent } from '../../models/TimelineModels';
import { MediaService } from '../../services/MediaService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0006;
const TAG = 'ImageMessage';

@Component
export struct ImageMessage {
  @Prop content: ImageContent;
  @State imageBase64: string = '';
  @State isLoading: boolean = true;
  @State loadError: boolean = false;
  @State errorMessage: string = '';

  async aboutToAppear(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'ImageMessage aboutToAppear: mxcUrl=%{public}s, encrypted=%{public}s',
      this.content.mxcUrl ?? 'null',
      this.content.encryptedFile ? 'yes' : 'no');

    // 如果是本地图片 (上传前)，直接显示
    if (this.content.localPath) {
      hilog.info(DOMAIN, TAG, 'Using local path: %{public}s', this.content.localPath);
      this.isLoading = false;
      return;
    }

    // 检查 mxcUrl 是否有效
    if (!this.content.mxcUrl || this.content.mxcUrl === '' || this.content.mxcUrl === 'undefined') {
      hilog.warn(DOMAIN, TAG, 'No valid mxcUrl, showing placeholder');
      this.isLoading = false;
      this.loadError = true;
      this.errorMessage = '无图片链接';
      return;
    }

    // 远程图片 - 下载
    try {
      this.imageBase64 = await MediaService.downloadImage(this.content);
      this.isLoading = false;
      hilog.info(DOMAIN, TAG, 'Image loaded successfully, base64 length: %{public}d', this.imageBase64.length);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Image download failed: %{public}s', error.message);
      this.isLoading = false;
      this.loadError = true;
      this.errorMessage = error.message;
    }
  }

  build() {
    Column() {
      if (this.isLoading) {
        // 加载中状态
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('加载图片...')
            .fontSize(12)
            .opacity(0.6)
            .margin({ top: 8 })
        }
        .width(200)
        .height(150)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
      } else if (this.loadError) {
        // 加载失败或无 URL 状态 - 显示占位符和错误信息
        Column() {
          Text('🖼️')
            .fontSize(32)
          Text(this.content.body ?? '图片')
            .fontSize(12)
            .opacity(0.6)
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.errorMessage) {
            Text(this.errorMessage)
              .fontSize(10)
              .fontColor('#FF5252')
              .opacity(0.8)
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          // 重试按钮
          Button('重试')
            .fontSize(12)
            .height(24)
            .backgroundColor('#2196F3')
            .fontColor('#FFFFFF')
            .margin({ top: 8 })
            .onClick(async () => {
              this.isLoading = true;
              this.loadError = false;
              try {
                this.imageBase64 = await MediaService.downloadImage(this.content);
                this.isLoading = false;
              } catch (err) {
                const error = err as Error;
                hilog.error(DOMAIN, TAG, 'Retry failed: %{public}s', error.message);
                this.isLoading = false;
                this.loadError = true;
                this.errorMessage = error.message;
              }
            })
        }
        .width(200)
        .height(180)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E8E8E8')
        .borderRadius(8)
      } else if (this.content.localPath) {
        // 本地图片 - 使用文件路径
        Image(this.content.localPath)
          .width(this.content.width ?? 200)
          .height(this.content.height ?? 150)
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
      } else if (this.imageBase64) {
        // 远程图片 - 使用 Base64，限制显示尺寸
        Image(`data:${this.content.mimetype ?? 'image/jpeg'};base64,${this.imageBase64}`)
          .width(Math.min(this.content.width ?? 200, 300))
          .height(Math.min(this.content.height ?? 150, 225))
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
      }
    }
    .width('100%')
  }
}