/**
 * ModelConfig - AI 模型配置
 *
 * 定义 AI 模型的配置接口和默认值。
 * 从 agent/types/ModelTypes.ets 迁移而来，统一管理模型配置。
 */

/**
 * AI 模型配置接口
 */
export interface ModelConfig {
  /** API 地址，如 "https://open.bigmodel.cn/api/paas/v4" */
  baseUrl: string;
  /** API 密钥 */
  apiKey: string;
  /** 模型名称，如 "autoglm-phone" */
  modelName: string;
  /** 最大输出 token 数 */
  maxTokens: number;
  /** 采样温度 */
  temperature: number;
  /** Top-P 采样 */
  topP: number;
  /** 频率惩罚 */
  frequencyPenalty: number;
  /** 请求超时时间（毫秒） */
  timeout: number;
}

/**
 * 默认模型配置
 * 与官方 AutoGLM 保持一致
 */
export const DEFAULT_MODEL_CONFIG: ModelConfig = {
  baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
  apiKey: '',
  modelName: 'autoglm-phone',
  maxTokens: 3000,
  temperature: 0.0,
  topP: 0.85,
  frequencyPenalty: 0.2,
  timeout: 120000
};
