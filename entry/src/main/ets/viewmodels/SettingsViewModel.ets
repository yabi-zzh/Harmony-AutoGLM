/**
 * SettingsViewModel - Settings 页面的 ViewModel
 * 
 * 负责管理 Settings 页面的 UI 状态和配置管理业务逻辑。
 * 使用 @Observed 装饰器实现响应式绑定。
 */

import { common } from '@kit.AbilityKit';
import { Message } from '../agent/types/ModelTypes';
import { ConfigManager } from '../agent/storage/ConfigManager';
import { ModelClient, ModelClientError } from '../agent/client/ModelClient';
import { DEFAULT_MODEL_CONFIG, ModelConfig } from '../models';

@Observed
export class SettingsViewModel {
  // UI 状态属性 - 使用 DEFAULT_MODEL_CONFIG 统一管理
  baseUrl: string = DEFAULT_MODEL_CONFIG.baseUrl;
  apiKey: string = DEFAULT_MODEL_CONFIG.apiKey;
  modelName: string = DEFAULT_MODEL_CONFIG.modelName;
  maxTokens: string = String(DEFAULT_MODEL_CONFIG.maxTokens);
  temperature: string = String(DEFAULT_MODEL_CONFIG.temperature);
  frequencyPenalty: string = String(DEFAULT_MODEL_CONFIG.frequencyPenalty);
  maxSteps: string = '100';
  timeout: string = String(DEFAULT_MODEL_CONFIG.timeout);
  isSaving: boolean = false;
  isTesting: boolean = false;

  // 私有成员
  private configManager: ConfigManager = ConfigManager.getInstance();

  // Toast 回调
  onShowToast?: (message: string) => void;

  /**
   * 初始化 ViewModel，加载已保存配置
   * @param context UIAbilityContext
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      await this.configManager.initialize(context);
      const config = await this.configManager.loadConfig();
      if (config) {
        this.baseUrl = config.baseUrl;
        this.apiKey = config.apiKey;
        this.modelName = config.modelName;
        this.maxTokens = String(config.maxTokens ?? DEFAULT_MODEL_CONFIG.maxTokens);
        this.temperature = String(config.temperature ?? DEFAULT_MODEL_CONFIG.temperature);
        this.frequencyPenalty = String(config.frequencyPenalty ?? DEFAULT_MODEL_CONFIG.frequencyPenalty);
        this.timeout = String(config.timeout ?? DEFAULT_MODEL_CONFIG.timeout);
      } else {
        // 没有保存过配置，自动保存默认配置
        await this.saveDefaultConfig();
      }
    } catch (error) {
      console.error('加载配置失败', error);
    }
  }

  /**
   * 保存默认配置
   */
  private async saveDefaultConfig(): Promise<void> {
    try {
      const config: ModelConfig = {
        baseUrl: this.baseUrl,
        apiKey: this.apiKey,
        modelName: this.modelName,
        maxTokens: parseInt(this.maxTokens) || DEFAULT_MODEL_CONFIG.maxTokens,
        temperature: parseFloat(this.temperature) || DEFAULT_MODEL_CONFIG.temperature,
        topP: DEFAULT_MODEL_CONFIG.topP,
        frequencyPenalty: parseFloat(this.frequencyPenalty) || DEFAULT_MODEL_CONFIG.frequencyPenalty,
        timeout: parseInt(this.timeout) || DEFAULT_MODEL_CONFIG.timeout
      };
      await this.configManager.saveConfig(config);
    } catch (error) {
      console.error('保存默认配置失败', error);
    }
  }

  /**
   * 保存配置
   */
  async saveConfig(): Promise<void> {
    const validation = ConfigManager.validateConfig({
      baseUrl: this.baseUrl,
      apiKey: this.apiKey,
      modelName: this.modelName
    });

    if (!validation.valid) {
      this.showToast(validation.errors[0]);
      return;
    }

    this.isSaving = true;

    try {
      const config: ModelConfig = {
        baseUrl: this.baseUrl,
        apiKey: this.apiKey,
        modelName: this.modelName,
        maxTokens: parseInt(this.maxTokens) || DEFAULT_MODEL_CONFIG.maxTokens,
        temperature: parseFloat(this.temperature) || DEFAULT_MODEL_CONFIG.temperature,
        topP: DEFAULT_MODEL_CONFIG.topP,
        frequencyPenalty: parseFloat(this.frequencyPenalty) || DEFAULT_MODEL_CONFIG.frequencyPenalty,
        timeout: parseInt(this.timeout) || DEFAULT_MODEL_CONFIG.timeout
      };

      await this.configManager.saveConfig(config);
      this.showToast('配置已保存');
    } catch (error) {
      this.showToast(`保存失败: ${error}`);
    } finally {
      this.isSaving = false;
    }
  }

  /**
   * 测试 API 连接
   */
  async testConnection(): Promise<void> {
    const validation = ConfigManager.validateConfig({
      baseUrl: this.baseUrl,
      apiKey: this.apiKey,
      modelName: this.modelName
    });

    if (!validation.valid) {
      this.showToast(validation.errors[0]);
      return;
    }

    this.isTesting = true;

    try {
      const testConfig: ModelConfig = {
        baseUrl: this.baseUrl,
        apiKey: this.apiKey,
        modelName: this.modelName,
        maxTokens: 100,
        temperature: 0,
        topP: DEFAULT_MODEL_CONFIG.topP,
        frequencyPenalty: DEFAULT_MODEL_CONFIG.frequencyPenalty,
        timeout: 30000
      };

      const client = new ModelClient(testConfig);
      
      const testMessages: Message[] = [
        ModelClient.createSystemMessage('You are a helpful assistant.'),
        ModelClient.createUserMessage('你好，请简单回复')
      ];
      
      const startTime = Date.now();
      await client.request(testMessages);
      const elapsed = Date.now() - startTime;
      this.showToast(`连接成功 (${elapsed}ms)`);
    } catch (error) {
      let errorMsg = '连接失败';
      if (error instanceof ModelClientError) {
        errorMsg = `${error.code}: ${error.message}`;
      } else if (error instanceof Error) {
        errorMsg = error.message;
      }
      console.error(`SettingsViewModel: API Test failed - ${errorMsg}`);
      this.showToast(errorMsg);
    } finally {
      this.isTesting = false;
    }
  }

  /**
   * 设置 API 地址
   */
  setBaseUrl(value: string): void {
    this.baseUrl = value;
  }

  /**
   * 设置 API 密钥
   */
  setApiKey(value: string): void {
    this.apiKey = value;
  }

  /**
   * 设置模型名称
   */
  setModelName(value: string): void {
    this.modelName = value;
  }

  /**
   * 设置最大 Token
   */
  setMaxTokens(value: string): void {
    this.maxTokens = value;
  }

  /**
   * 设置温度
   */
  setTemperature(value: string): void {
    this.temperature = value;
  }

  /**
   * 设置频率惩罚
   */
  setFrequencyPenalty(value: string): void {
    this.frequencyPenalty = value;
  }

  /**
   * 设置最大步骤
   */
  setMaxSteps(value: string): void {
    this.maxSteps = value;
  }

  /**
   * 设置超时时间
   */
  setTimeout(value: string): void {
    this.timeout = value;
  }

  /**
   * 显示 Toast 消息
   */
  private showToast(message: string): void {
    if (this.onShowToast) {
      this.onShowToast(message);
    }
  }
}
