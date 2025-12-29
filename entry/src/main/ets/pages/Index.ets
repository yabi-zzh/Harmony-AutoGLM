/**
 * 主页 - 设备连接与入口
 * 
 * 使用 MVVM 架构，通过 IndexViewModel 管理状态 and 业务逻辑
 */

import { PromptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HdcClient } from 'hdclib';
import { TaskPage } from './TaskPage';
import { SettingsPage } from './SettingsPage';
import { IndexViewModel } from '../viewmodels/IndexViewModel';

@Entry
@Component
struct Index {
  @State viewModel: IndexViewModel = new IndexViewModel();
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();

  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    // 设置 Toast 回调
    this.viewModel.onShowToast = (message: string): void => {
      try {
        this.promptAction.showToast({ message: message, duration: 2000 });
      } catch (e) {
        // Toast 显示失败，忽略
      }
    };

    // 使用微任务初始化 ViewModel，避免阻塞首帧渲染
    Promise.resolve().then(() => {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.viewModel.initialize(context);
    });
  }

  aboutToDisappear(): void {
    // 清理 HDC 资源
    if (this.viewModel.connectedDevice) {
      HdcClient.disconnect();
    }
    HdcClient.cleanup();
  }

  @Builder
  PageMap(name: string) {
    if (name === 'TaskPage') {
      TaskPage()
    } else if (name === 'SettingsPage') {
      SettingsPage()
    }
  }

  build() {
    Navigation(this.pageStack) {
      IndexContent({ 
        viewModel: this.viewModel, 
        pageStack: this.pageStack 
      })
    }
    .hideTitleBar(true)
    .navDestination(this.PageMap)
  }
}

@Component
struct IndexContent {
  @ObjectLink viewModel: IndexViewModel;
  @Link pageStack: NavPathStack;

  @Builder
  TipItem(tipText: string) {
    Row() {
      Circle({ width: 4, height: 4 })
        .fill($r('sys.color.brand'))
        .margin({ right: 8, top: 7 })
      Text(tipText)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeight(18)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  @Builder
  InfoRow(label: string, value: string, symbol?: Resource) {
    if (value && value !== '-') {
      Row() {
        if (symbol) {
          Stack() {
            SymbolGlyph(symbol)
              .fontSize(14)
              .fontColor([$r('sys.color.brand')])
          }
          .width(30)
          .height(30)
          .backgroundColor('#0D007DFF')
          .borderRadius(8)
          .margin({ right: 12 })
        }
        
        Text(label)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .flexShrink(0)
        
        Blank().flexShrink(1)
        
        Text(value)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .textAlign(TextAlign.End)
          .layoutWeight(1)
          .margin({ left: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Column() {
      // 顶部标题
      Row() {
        Column() {
          Text('Next AI Agent')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Row() {
            Rect()
              .width(4)
              .height(14)
              .fill($r('sys.color.brand'))
              .radius(2)
              .margin({ right: 6 })
            Text('智能自动化助手')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .letterSpacing(1)
          }
          .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width(40)
        .height(40)
        .backgroundColor($r('sys.color.background_tertiary'))
        .borderRadius(20)
        .onClick(() => {
          this.pageStack.pushPathByName('SettingsPage', null);
        })
      }
      .width('100%')
      .padding({ left: 26, right: 26, top: 40, bottom: 16 })

      if (!this.viewModel.isInitialized) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('sys.color.brand'))
          Text('正在初始化...')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          Column({ space: 16 }) { // 适度放宽间距，增加高级感
            // 1. 连接状态卡片
            Column() {
              Row() {
                Stack() {
                  Circle()
                    .width(54)
                    .height(54)
                    .fill(this.viewModel.connectedDevice ? '#1A00AA44' : $r('sys.color.background_secondary'))
                  SymbolGlyph(this.viewModel.connectedDevice ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.link_slash'))
                    .fontSize(28) // 略微放大图标
                    .fontColor([this.viewModel.connectedDevice ? '#00AA44' : $r('sys.color.font_secondary')])
                }
                Column() {
                  Text(this.viewModel.connectedDevice ? '设备已连接' : '等待设备连接')
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                  Text(this.viewModel.connectedDevice ? 'HDC 服务运行中' : this.viewModel.connectionStatus)
                    .fontSize(12)
                    .fontColor(this.viewModel.connectedDevice ? '#00AA44' : (this.viewModel.connectionStatus === '连接失败' ? $r('sys.color.warning') : $r('sys.color.font_secondary')))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 16 })
                .layoutWeight(1)

                  if (this.viewModel.connectedDevice) {
                    Button('断开连接')
                      .fontSize(12)
                      .fontColor($r('sys.color.warning'))
                      .backgroundColor('#1AFA2A2D') // 增强一点对比度
                      .height(28)
                      .padding({ left: 10, right: 10 })
                      .borderRadius(14)
                      .onClick(async () => await this.viewModel.disconnectDevice())
                  }
              }
              .width('100%')

              if (!this.viewModel.connectedDevice) {
                Divider().margin({ top: 16, bottom: 12 }).color($r('sys.color.comp_divider'))
                Row() {
                  Text('HDC 环境')
                    .fontSize(13)
                    .fontColor($r('sys.color.font_secondary'))
                  Blank()
                  Row() {
                    Circle({ width: 6, height: 6 })
                      .fill('#00AA44')
                      .margin({ right: 6 })
                    Text(HdcClient.version())
                      .fontSize(13)
                      .fontColor($r('sys.color.font_primary'))
                      .fontWeight(FontWeight.Medium)
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('sys.color.background_primary'))
            .borderRadius(24)
            .border({ width: 0.5, color: '#0D000000' })
            .shadow({ radius: 20, color: '#08000000', offsetY: 4 })

            // 2. 设备信息（已连接时显示）
            if (this.viewModel.connectedDevice) {
              Column() {
                Row() {
                  Rect()
                    .width(3)
                    .height(14)
                    .fill($r('sys.color.brand'))
                    .radius(1.5)
                    .margin({ right: 8 })
                  Text('设备详情')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                }
                .width('100%')
                .margin({ bottom: 16 })

                Column({ space: 18 }) { // 增加内容行间距
                  this.InfoRow('名称', this.viewModel.deviceName)
                  this.InfoRow('型号', this.viewModel.deviceModel)
                  this.InfoRow('系统', this.viewModel.systemVersion)
                  this.InfoRow('版本', this.viewModel.ohosFullName)
                  this.InfoRow('API', this.viewModel.apiVersion ? `API ${this.viewModel.apiVersion}` : '')
                  this.InfoRow('CPU', this.viewModel.cpuAbiList)
                  this.InfoRow('地址', this.viewModel.connectedDevice)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 20, bottom: 20 }) // 增加上下内边距，更有呼吸感
              .backgroundColor($r('sys.color.background_primary'))
              .borderRadius(24)
              .border({ width: 0.5, color: '#0D000000' })
              .shadow({ radius: 25, color: '#05000000', offsetY: 8 })
            }

            // 3. 手动连接 (仅在未连接时显示)
            if (!this.viewModel.connectedDevice) {
              Column() {
                Row() {
                  Rect()
                    .width(3)
                    .height(14)
                    .fill($r('sys.color.brand'))
                    .radius(1.5)
                    .margin({ right: 8 })
                  Text('手动连接')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                }
                .margin({ bottom: 12 })

                Row({ space: 12 }) {
                  TextInput({ placeholder: 'IP 地址', text: this.viewModel.ipAddress })
                    .layoutWeight(3)
                    .height(48)
                    .backgroundColor($r('sys.color.background_secondary'))
                    .borderRadius(20) // 提升圆角，与胶囊按钮更统一
                    .onChange((value: string) => this.viewModel.setIpAddress(value))

                  TextInput({ placeholder: '端口', text: this.viewModel.port })
                    .layoutWeight(1.2)
                    .height(48)
                    .backgroundColor($r('sys.color.background_secondary'))
                    .borderRadius(20) // 提升圆角
                    .type(InputType.Number)
                    .onChange((value: string) => this.viewModel.setPort(value))
                }

                Button() {
                  Row() {
                    if (this.viewModel.isConnecting) {
                      LoadingProgress()
                        .width(20)
                        .height(20)
                        .margin({ right: 8 })
                        .color(Color.White)
                    }
                    Text(this.viewModel.isConnecting ? '正在连接...' : '连接设备')
                      .fontColor(Color.White)
                      .fontWeight(FontWeight.Bold)
                      .fontSize(15)
                  }
                }
                .width('100%')
                .height(48)
                .margin({ top: 12 })
                .linearGradient({
                  direction: GradientDirection.Right,
                  colors: [['#007DFF', 0.0], ['#409EFF', 1.0]]
                })
                .borderRadius(24)
                .shadow({ radius: 10, color: '#20007DFF', offsetY: 4 })
                .enabled(!this.viewModel.isConnecting)
                .onClick(() => this.viewModel.connectDevice())
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(16)
              .backgroundColor($r('sys.color.background_primary'))
              .borderRadius(24)
              .border({ width: 0.5, color: '#0D000000' })
            }

            // 4. 帮助与说明 (整合原本散乱的板块，增强视觉整体感)
            if (!this.viewModel.connectedDevice) {
              Column() {
                // 准备工作部分
                Column({ space: 10 }) {
                  Row() {
                    Rect()
                      .width(3)
                      .height(14)
                      .fill($r('sys.color.brand'))
                      .radius(1.5)
                      .margin({ right: 8 })
                    Text('准备工作')
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('sys.color.font_primary'))
                  }
                  Column({ space: 6 }) {
                    this.TipItem('确保手机与电脑处于同一局域网')
                    this.TipItem('在手机"开发者选项"中开启"无线调试"')
                    this.TipItem('查看 IP 和端口并输入到上方')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')

                Divider()
                  .color($r('sys.color.comp_divider'))
                  .opacity(0.5)
                  .margin({ top: 16, bottom: 16 })

                // 关于部分
                Column({ space: 8 }) {
                  Text('关于') // 精简标题
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                  Text('融合 AutoGLM 感知能力与 HarmonyOS NEXT 原生操控接口，支持屏幕内容理解、自然语言指令转化与自动化执行。')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .lineHeight(18)
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .margin({ top: 8 }) // 增加间距，使其上下对称
              }
              .padding(16)
              .backgroundColor($r('sys.color.background_primary'))
              .borderRadius(24)
              .border({ width: 0.5, color: '#0D000000' })
            }

            // 5. 错误信息
            if (this.viewModel.errorMessage) {
              Row() {
                SymbolGlyph($r('sys.symbol.exclamationmark_circle_fill'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.warning')])
                  .margin({ right: 8 })
                Text(this.viewModel.errorMessage)
                  .fontSize(12)
                  .fontColor($r('sys.color.warning'))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#1AFA2A2D')
              .borderRadius(12)
            }
            
            Blank() 
          }
          .width('100%')
          .height('100%')
          .padding({ 
            left: 20, 
            right: 20, 
            bottom: this.viewModel.connectedDevice ? 110 : 60 
          })

          // 底部固定页脚
          Column() {
            if (this.viewModel.connectedDevice) {
              Button() {
                Row() {
                  Text('执行 AI 任务')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                }
              }
              .width('100%')
              .height(52)
              .linearGradient({
                direction: GradientDirection.Right,
                colors: [['#007DFF', 0.0], ['#409EFF', 1.0]]
              })
              .borderRadius(26)
              .shadow({ radius: 15, color: '#33007DFF', offsetY: 6 })
              .onClick(() => this.startAITask())
              .margin({ bottom: 12 })
            }

            Row() {
              Text('Powered by AutoGLM')
                .fontSize(10)
                .fontColor($r('sys.color.font_tertiary'))
              Text(' · ')
                .fontSize(10)
                .fontColor($r('sys.color.font_tertiary'))
              Text('Next AI Agent v1.0.0')
                .fontSize(10)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .padding({ 
            left: 24, 
            right: 24, 
            bottom: 24, 
            top: this.viewModel.connectedDevice ? 16 : 12 
          })
          .backgroundBlurStyle(this.viewModel.connectedDevice ? BlurStyle.COMPONENT_ULTRA_THICK : BlurStyle.NONE)
          .border({ 
            width: { top: this.viewModel.connectedDevice ? 0.5 : 0 }, 
            color: '#0D000000' 
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }

  private startAITask(): void {
    AppStorage.setOrCreate('connectedDevice', this.viewModel.connectedDevice);
    this.pageStack.pushPathByName('TaskPage', this.viewModel.connectedDevice);
  }
}
