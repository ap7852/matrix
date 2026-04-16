/**
 * Element X HarmonyOS - 主页面
 *
 * 测试 Rust NAPI 桥接层功能
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import matrixBridge from 'libmatrix_bridge.so';

const DOMAIN = 0x0000;
const TAG = 'MatrixBridge';

@Entry
@Component
struct Index {
  @State message: string = 'Element X HarmonyOS';
  @State rustHello: string = '';
  @State ringHash: string = '';
  @State asyncResult: string = '';

  aboutToAppear(): void {
    // 初始化 NAPI 运行时
    hilog.info(DOMAIN, TAG, 'Initializing Rust NAPI bridge...');
    try {
      // 调用 Rust Hello World
      this.rustHello = matrixBridge.hello();
      hilog.info(DOMAIN, TAG, 'Rust hello: %{public}s', this.rustHello);

      // 验证 ring 编译成功
      this.ringHash = matrixBridge.verifyRingCompile();
      hilog.info(DOMAIN, TAG, 'Ring hash: %{public}s', this.ringHash);

      // 测试 add 函数 (替代原有 C++ NAPI)
      const sum = matrixBridge.add(2, 3);
      hilog.info(DOMAIN, TAG, 'add(2, 3) = %{public}d', sum);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'NAPI call failed: %{public}s', JSON.stringify(e));
    }
  }

  build() {
    Column() {
      // 标题
      Text(this.message)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })

      // Rust 桥接状态
      Column() {
        Text('Rust NAPI 桥接状态')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 10 })

        Text(`✅ ${this.rustHello}`)
          .fontSize(14)
          .fontColor('#4CAF50')
          .margin({ bottom: 5 })

        Text(`Ring SHA256: ${this.ringHash}`)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 5 })

        Text(`add(2,3) = ${matrixBridge.add(2, 3)}`)
          .fontSize(12)
          .fontColor('#666666')
      }
      .padding(16)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      .margin({ bottom: 20 })

      // 异步测试按钮
      Button('测试异步 Hello')
        .width('80%')
        .onClick(async () => {
          try {
            this.asyncResult = await matrixBridge.helloAsync('HarmonyOS');
            hilog.info(DOMAIN, TAG, 'Async result: %{public}s', this.asyncResult);
          } catch (e) {
            this.asyncResult = `Error: ${JSON.stringify(e)}`;
            hilog.error(DOMAIN, TAG, 'Async call failed: %{public}s', this.asyncResult);
          }
        })

      if (this.asyncResult) {
        Text(this.asyncResult)
          .fontSize(14)
          .margin({ top: 10 })
          .fontColor('#2196F3')
      }

      // 初始化按钮
      Button('初始化 Runtime')
        .width('80%')
        .margin({ top: 10 })
        .onClick(() => {
          try {
            matrixBridge.init();
            hilog.info(DOMAIN, TAG, 'Runtime initialized');
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'Init failed: %{public}s', JSON.stringify(e));
          }
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }
}