/**
 * 配置管理器
 * 负责保存和加载模型配置到本地存储
 */

import preferences from '@ohos.data.preferences';
import { APP_CONFIG, DEFAULT_MODEL_CONFIG, ModelConfig } from '../../models';

/**
 * 配置验证结果
 */
export interface ConfigValidationResult {
  valid: boolean;
  errors: string[];
}

/**
 * 配置管理器类
 */
export class ConfigManager {
  private static instance: ConfigManager | null = null;
  private preferences: preferences.Preferences | null = null;

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): ConfigManager {
    if (!ConfigManager.instance) {
      ConfigManager.instance = new ConfigManager();
    }
    return ConfigManager.instance;
  }

  /**
   * 初始化配置管理器
   * @param context 应用上下文
   */
  async initialize(context: Context): Promise<void> {
    try {
      this.preferences = await preferences.getPreferences(context, APP_CONFIG.storage.preferencesName);
    } catch (error) {
      console.error('ConfigManager: 初始化失败', error);
      throw new Error('ConfigManager 初始化失败');
    }
  }

  /**
   * 保存模型配置
   * @param config 模型配置
   */
  async saveConfig(config: ModelConfig): Promise<void> {
    if (!this.preferences) {
      throw new Error('ConfigManager 未初始化');
    }

    try {
      const configStr = JSON.stringify(config);
      await this.preferences.put(APP_CONFIG.storage.configKey, configStr);
      await this.preferences.flush();
    } catch (error) {
      console.error('ConfigManager: 保存配置失败', error);
      throw new Error('保存配置失败');
    }
  }

  /**
   * 加载模型配置
   * @returns 模型配置，如果不存在则返回 null
   */
  async loadConfig(): Promise<ModelConfig | null> {
    if (!this.preferences) {
      throw new Error('ConfigManager 未初始化');
    }

    try {
      const configStr = await this.preferences.get(APP_CONFIG.storage.configKey, '') as string;
      if (!configStr) {
        return null;
      }

      const config = JSON.parse(configStr) as ModelConfig;

      // 合并默认值
      return {
        baseUrl: config.baseUrl ?? DEFAULT_MODEL_CONFIG.baseUrl,
        apiKey: config.apiKey ?? DEFAULT_MODEL_CONFIG.apiKey,
        modelName: config.modelName ?? DEFAULT_MODEL_CONFIG.modelName,
        maxTokens: config.maxTokens ?? DEFAULT_MODEL_CONFIG.maxTokens,
        temperature: config.temperature ?? DEFAULT_MODEL_CONFIG.temperature,
        topP: config.topP ?? DEFAULT_MODEL_CONFIG.topP,
        frequencyPenalty: config.frequencyPenalty ?? DEFAULT_MODEL_CONFIG.frequencyPenalty,
        timeout: config.timeout ?? DEFAULT_MODEL_CONFIG.timeout
      };
    } catch (error) {
      console.error('ConfigManager: 加载配置失败', error);
      return null;
    }
  }

  /**
   * 检查是否有保存的配置
   */
  async hasConfig(): Promise<boolean> {
    if (!this.preferences) {
      return false;
    }

    try {
      const configStr = await this.preferences.get(APP_CONFIG.storage.configKey, '') as string;
      return configStr !== '';
    } catch (error) {
      return false;
    }
  }

  /**
   * 清除配置
   */
  async clearConfig(): Promise<void> {
    if (!this.preferences) {
      throw new Error('ConfigManager 未初始化');
    }

    try {
      await this.preferences.delete(APP_CONFIG.storage.configKey);
      await this.preferences.flush();
    } catch (error) {
      console.error('ConfigManager: 清除配置失败', error);
      throw new Error('清除配置失败');
    }
  }

  /**
   * 验证配置结果
   */
  static validateConfig(config: Partial<ModelConfig>): ConfigValidationResult {
    const errors: string[] = [];

    if (!config.baseUrl || config.baseUrl.trim() === '') {
      errors.push('API 地址不能为空');
    } else if (!config.baseUrl.startsWith('http://') && !config.baseUrl.startsWith('https://')) {
      errors.push('API 地址必须以 http:// 或 https:// 开头');
    }

    if (!config.apiKey || config.apiKey.trim() === '') {
      errors.push('API 密钥不能为空');
    }

    if (!config.modelName || config.modelName.trim() === '') {
      errors.push('模型名称不能为空');
    }

    const result: ConfigValidationResult = {
      valid: errors.length === 0,
      errors: errors
    };
    return result;
  }
}
