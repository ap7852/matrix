/**
 * 主页面 - Navigation 容器
 */

import { initMatrixBridge, isBridgeReady, getInitError } from '../services/MatrixBridge';
import { AuthService } from '../services/AuthService';
import { LoginPage } from './LoginPage';
import { RoomListPage } from './RoomListPage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'MainPage';

@Entry
@Component
struct MainPage {
  @Provide('navPathStack') navPathStack: NavPathStack = new NavPathStack();
  @Provide('isAuthenticated') isAuthenticated: boolean = false;
  @State isInitialized: boolean = false;
  @State initFailed: boolean = false;
  @State initErrorMessage: string = '';

  async aboutToAppear(): Promise<void> {
    // 初始化 AuthService 的数据目录
    try {
      const context = getContext(this) as common.UIAbilityContext;
      AuthService.init(context);
      hilog.info(DOMAIN, TAG, 'AuthService initialized with dataDir: %{public}s', context.filesDir);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Failed to get context: %{public}s', error.message);
      this.initFailed = true;
      this.initErrorMessage = '无法获取应用上下文';
      return;
    }

    const success = await initMatrixBridge();
    if (success) {
      this.isInitialized = true;
      hilog.info(DOMAIN, TAG, 'Bridge initialized successfully');

      if (AuthService.hasSession()) {
        const session = await AuthService.restoreSession();
        if (session) {
          this.isAuthenticated = true;
          hilog.info(DOMAIN, TAG, 'Session restored: %{public}s', session.userId);
        }
      }
    } else {
      this.initFailed = true;
      this.initErrorMessage = getInitError() ?? '初始化失败';
      hilog.error(DOMAIN, TAG, 'Bridge init failed: %{public}s', this.initErrorMessage);
    }
  }

  build() {
    Navigation(this.navPathStack) {
      if (this.initFailed) {
        Column() {
          Text('初始化失败')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF5252')
          Text(this.initErrorMessage)
            .fontSize(14)
            .opacity(0.6)
            .margin({ top: 8 })
          Button('重试')
            .margin({ top: 24 })
            .onClick(async () => {
              this.initFailed = false;
              const success = await initMatrixBridge();
              if (success) {
                this.isInitialized = true;
              } else {
                this.initFailed = true;
                this.initErrorMessage = getInitError() ?? '初始化失败';
              }
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (!this.isInitialized) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('初始化中...')
            .fontSize(14)
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.isAuthenticated) {
        RoomListPage()
      } else {
        LoginPage()
      }
    }
    .mode(NavigationMode.Stack)
  }
}