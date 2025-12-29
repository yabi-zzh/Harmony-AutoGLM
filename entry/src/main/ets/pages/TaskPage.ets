/**
 * 任务页面 - AI 任务执行和消息展示
 * 
 * 使用 MVVM 架构，通过 TaskViewModel 管理状态和业务逻辑
 */

import { inputMethod } from '@kit.IMEKit';
import { common } from '@kit.AbilityKit';
import { TaskViewModel } from '../viewmodels/TaskViewModel';
import { ChatMessage, MessageType } from '../models';

/**
 * 消息项组件 - 使用 @ObjectLink 绑定 ChatMessage 实现响应式更新
 */
@Component
struct MessageItemView {
  @ObjectLink message: ChatMessage;
  formatTime: (timestamp: number) => string = () => '';
  getMessageTitle: (type: MessageType) => string = () => '';

  build() {
    Column() {
      if (this.message.type === MessageType.User) {
        // 用户消息 - 右侧显示时间
        Row() {
          Text(this.formatTime(this.message.timestamp))
            .fontSize(10)
            .fontColor($r('sys.color.font_tertiary'))
            .alignSelf(ItemAlign.End)
            .margin({ right: 8, bottom: 4 })
          Text(this.message.content)
            .fontSize(15)
            .fontColor($r('sys.color.white'))
            .lineHeight(22)
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor($r('sys.color.brand'))
            .borderRadius({
              topLeft: 18,
              topRight: 4,
              bottomLeft: 18,
              bottomRight: 18
            })
            .constraintSize({ maxWidth: '75%' })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 12 })
      } else {
        Column() {
          Row() {
            Text(this.getMessageTitle(this.message.type))
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .fontWeight(FontWeight.Bold)

            if (this.message.actionType) {
              Text(this.message.actionType.toUpperCase())
                .fontSize(10)
                .fontColor($r('sys.color.brand'))
                .fontWeight(FontWeight.Bold)
                .margin({ left: 8 })
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor($r('sys.color.background_secondary'))
                .borderRadius(4)
            }

            Text(this.formatTime(this.message.timestamp))
              .fontSize(10)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ left: 8 })
          }
          .margin({ bottom: 6, left: 4 })

          Column() {
            Text(this.message.content)
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
              .lineHeight(22)
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          }
          .backgroundColor($r('sys.color.background_secondary'))
          .borderRadius({
            topLeft: 4,
            topRight: 18,
            bottomLeft: 18,
            bottomRight: 18
          })
          .constraintSize({ maxWidth: '90%' })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 12 })
      }
    }
  }
}

@Component
export struct TaskPage {
  @State viewModel: TaskViewModel = new TaskViewModel();
  @Consume('pageStack') pageStack: NavPathStack;
  private scroller: Scroller = new Scroller();
  private scrollThrottleTimer: number = 0;

  async aboutToAppear() {
    // 设置滚动回调 - 使用节流避免频繁滚动
    this.viewModel.onScrollToBottom = (): void => {
      // 节流：100ms 内只执行一次滚动
      if (this.scrollThrottleTimer === 0) {
        this.scroller.scrollEdge(Edge.Bottom);
        this.scrollThrottleTimer = setTimeout(() => {
          this.scrollThrottleTimer = 0;
          // 节流结束后再滚动一次，确保显示最新内容
          this.scroller.scrollEdge(Edge.Bottom);
        }, 100) as number;
      }
    };

    // 初始化 ViewModel（统一执行 UITest初始化、获取屏幕尺寸、获取应用列表）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.viewModel.initialize(context);
  }

  build() {
    NavDestination() {
      TaskContent({ 
        viewModel: this.viewModel, 
        pageStack: this.pageStack,
        scroller: this.scroller
      })
    }
    .title('AI 任务')
    .backgroundColor($r('sys.color.background_primary'))
    .mode(NavDestinationMode.STANDARD)
    .onBackPressed(() => {
      this.pageStack.pop();
      return true;
    })
    .onShown(() => {
      // 每次页面显示时重新加载配置
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.viewModel.reloadConfig(context);
    })
  }
}

@Component
struct TaskContent {
  @ObjectLink viewModel: TaskViewModel;
  @Link pageStack: NavPathStack;
  scroller: Scroller = new Scroller();

  build() {
    Column() {
      // 配置错误提示
      if (!this.viewModel.isConfigured && this.viewModel.configError) {
        Row() {
          Text('提示: ' + this.viewModel.configError)
            .fontSize(13)
            .fontColor($r('sys.color.warning'))
            .layoutWeight(1)
          Text('去配置')
            .fontSize(13)
            .fontColor($r('sys.color.brand'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.pageStack.pushPathByName('SettingsPage', null))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .expandSafeArea([SafeAreaType.KEYBOARD])
        .zIndex(2)
      }

      // 状态栏 - 固定在顶部，不随键盘移动
      Row() {
        Circle({ width: 6, height: 6 })
          .fill(this.viewModel.getStatusColor())
        Text(this.viewModel.getStatusText())
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ left: 6 })
        if (this.viewModel.isRunning) {
          Text(` · 步骤 ${this.viewModel.stepCount}`)
            .fontSize(12)
            .fontColor($r('sys.color.brand'))
        }
        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .backgroundColor($r('sys.color.background_primary'))
      .border({ width: { bottom: 0.5 }, color: $r('sys.color.comp_divider') })
      .expandSafeArea([SafeAreaType.KEYBOARD])
      .zIndex(1)

      // 消息列表或加载动画
      if (this.viewModel.isInitializing) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('sys.color.brand'))
          Text(this.viewModel.initMessage)
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.background_primary'))
        .onClick(async () => {
          try {
            await inputMethod.getController().stopInputSession();
          } catch (err) {
            // 忽略输入法关闭异常
          }
        })
      } else if (this.viewModel.messages.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.ellipsis_message'))
            .fontSize(64)
            .fontColor([$r('sys.color.font_tertiary')])
          Text('描述你想完成的任务，AI 将自动为你执行')
            .fontSize(14)
            .fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 16 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.background_primary'))
        .onClick(async () => {
          try {
            await inputMethod.getController().stopInputSession();
          } catch (err) {
            // 忽略输入法关闭异常
          }
        })
      } else {
        List({ scroller: this.scroller }) {
          ForEach(this.viewModel.messages, (message: ChatMessage) => {
            ListItem() {
              MessageItemView({
                message: message,
                formatTime: (ts: number): string => this.viewModel.formatTime(ts),
                getMessageTitle: (type: MessageType): string => this.viewModel.getMessageTitle(type)
              })
            }
          }, (message: ChatMessage) => message.id.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('sys.color.background_primary'))
        .edgeEffect(EdgeEffect.Spring)
        .onClick(async () => {
          try {
            await inputMethod.getController().stopInputSession();
          } catch (err) {
            // 忽略输入法关闭异常
          }
        })
      }

      // 输入区域
      Column() {
        Row({ space: 10 }) {
          TextArea({ placeholder: '描述你想完成的任务...', text: this.viewModel.inputText })
            .layoutWeight(1)
            .constraintSize({ minHeight: 40, maxHeight: 120 })
            .backgroundColor($r('sys.color.background_secondary'))
            .borderRadius(12)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .enabled(!this.viewModel.isRunning && this.viewModel.isConfigured)
            .onChange((value: string) => this.viewModel.setInputText(value))

          Button() {
            SymbolGlyph(this.viewModel.isRunning ? $r('sys.symbol.square_fill') : $r('sys.symbol.paperplane_fill'))
              .fontSize(20)
              .fontColor([$r('sys.color.white')])
          }
          .width(40)
          .height(40)
          .backgroundColor(this.viewModel.isRunning ? $r('sys.color.warning') : $r('sys.color.brand'))
          .borderRadius(12)
          .enabled(this.viewModel.isConfigured || this.viewModel.isRunning)
          .alignSelf(ItemAlign.End)
          .onClick(() => {
            if (this.viewModel.isRunning) {
              this.viewModel.stopTask();
            } else {
              this.viewModel.sendTask();
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12, top: 12 })
      }
      .backgroundColor($r('sys.color.background_primary'))
      .border({ width: { top: 0.5 }, color: $r('sys.color.comp_divider') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
