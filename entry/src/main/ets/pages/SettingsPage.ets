/**
 * 设置页面 - 模型配置管理
 * 
 * 使用 MVVM 架构，通过 SettingsViewModel 管理状态和业务逻辑
 */

import { PromptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SettingsViewModel } from '../viewmodels/SettingsViewModel';

@Component
export struct SettingsPage {
  @State viewModel: SettingsViewModel = new SettingsViewModel();
  @Consume('pageStack') pageStack: NavPathStack;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  async aboutToAppear() {
    // 设置 Toast 回调
    this.viewModel.onShowToast = (message: string): void => {
      try {
        this.promptAction.showToast({ message: message, duration: 2000 });
      } catch (e) {
        console.error('showToast error', e);
      }
    };

    // 初始化 ViewModel
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.viewModel.initialize(context);
  }

  build() {
    NavDestination() {
      SettingsContent({ viewModel: this.viewModel })
    }
    .title('模型配置')
    .backgroundColor($r('sys.color.background_secondary'))
    .onBackPressed(() => {
      this.pageStack.pop();
      return true;
    })
  }
}

@Component
struct SettingsContent {
  @ObjectLink viewModel: SettingsViewModel;

  @Builder
  InputItem(label: string, placeholder: string, text: string, onChange: (v: string) => void, type: InputType = InputType.Normal) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .margin({ bottom: 8, left: 2 })
      
      TextInput({ placeholder: placeholder, text: text })
        .width('100%')
        .height(48)
        .backgroundColor($r('sys.color.background_secondary'))
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .type(type)
        .onChange(onChange)
    }
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      List({ space: 12 }) {
        // 基础配置
        ListItem() {
          Column() {
            Text('基础配置')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ bottom: 8, left: 4 })
              .width('100%')

            Column({ space: 16 }) {
              this.InputItem('API 地址', '输入 API 地址 (例如: https://api.openai.com/v1)', this.viewModel.baseUrl, (v: string) => this.viewModel.setBaseUrl(v))
              
              Column() {
                Text('API 密钥')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                  .margin({ bottom: 8, left: 2 })
                
                TextInput({ placeholder: '输入 API 密钥', text: this.viewModel.apiKey })
                  .width('100%')
                  .height(48)
                  .backgroundColor($r('sys.color.background_secondary'))
                  .borderRadius(12)
                  .padding({ left: 12, right: 12 })
                  .type(InputType.Password)
                  .showPasswordIcon(true)
                  .onChange((v: string) => this.viewModel.setApiKey(v))
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              this.InputItem('模型名称', '输入模型名称 (例如: glm-4v-flash)', this.viewModel.modelName, (v: string) => this.viewModel.setModelName(v))
              
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('sys.color.background_primary'))
            .borderRadius(16)
            .shadow({ radius: 10, color: '#05000000' })
          }
        }
        .padding({ left: 16, right: 16, top: 4 })

        // 模型参数
        ListItem() {
          Column() {
            Text('模型参数')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ bottom: 8, left: 4 })
              .width('100%')

            Column({ space: 16 }) {
              Row({ space: 12 }) {
                Column() {
                  this.InputItem('最大 Token', '3000', this.viewModel.maxTokens, (v: string) => this.viewModel.setMaxTokens(v), InputType.Number)
                }.layoutWeight(1)

                Column() {
                  this.InputItem('温度', '0.0', this.viewModel.temperature, (v: string) => this.viewModel.setTemperature(v))
                }.layoutWeight(1)
              }

              Row({ space: 12 }) {
                Column() {
                  this.InputItem('最大步骤', '100', this.viewModel.maxSteps, (v: string) => this.viewModel.setMaxSteps(v), InputType.Number)
                }.layoutWeight(1)

                Column() {
                  this.InputItem('超时 (ms)', '120000', this.viewModel.timeout, (v: string) => this.viewModel.setTimeout(v), InputType.Number)
                }.layoutWeight(1)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('sys.color.background_primary'))
            .borderRadius(16)
            .shadow({ radius: 10, color: '#05000000' })
          }
        }
        .padding({ left: 16, right: 16 })

        // 底部留白和按钮
        ListItem() {
          Row({ space: 12 }) {
            Button('测试连接')
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .borderRadius(10)
              .enabled(!this.viewModel.isTesting && !this.viewModel.isSaving)
              .onClick(() => this.viewModel.testConnection())

            Button('保存配置')
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('sys.color.brand'))
              .fontColor($r('sys.color.white'))
              .fontWeight(FontWeight.Bold)
              .borderRadius(10)
              .enabled(!this.viewModel.isTesting && !this.viewModel.isSaving)
              .onClick(() => this.viewModel.saveConfig())
          }
          .width('100%')
          .padding({ top: 12, bottom: 40 })
        }
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
