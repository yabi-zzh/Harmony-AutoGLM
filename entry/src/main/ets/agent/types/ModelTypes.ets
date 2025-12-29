/**
 * AI 模型相关类型定义
 * 
 * 注意：ModelConfig 和 DEFAULT_MODEL_CONFIG 已迁移到 models/ModelConfig.ets
 * 本文件保留 API 通信相关的类型定义
 */

// 重新导出 models 中的配置类型以保持向后兼容
export { ModelConfig, DEFAULT_MODEL_CONFIG } from '../../models';

/**
 * 文本内容
 */
export interface TextContent {
  type: "text";
  text: string;
}

/**
 * 图片 URL 信息
 */
export interface ImageUrlInfo {
  url: string; // "data:image/png;base64,..."
}

/**
 * 图片内容
 */
export interface ImageContent {
  type: "image_url";
  image_url: ImageUrlInfo;
}

/**
 * 内容项基类
 */
export interface ContentItem {
  type: string;
}

/**
 * 消息内容数组类型
 */
export type ContentArray = (TextContent | ImageContent)[];

/**
 * 消息角色
 */
export type MessageRole = "system" | "user" | "assistant";

/**
 * 消息
 */
export interface Message {
  role: MessageRole;
  content: string | ContentArray;
}

/**
 * 模型响应
 */
export interface ModelResponse {
  /** AI 思考过程 */
  thinking: string;
  /** 原始动作字符串 */
  actionRaw: string;
  /** 总耗时（毫秒） */
  totalTime?: number;
}

/**
 * API 请求体
 */
export interface ChatCompletionRequest {
  model: string;
  messages: Message[];
  max_tokens?: number;
  temperature?: number;
  top_p?: number;
  frequency_penalty?: number;
  stream?: boolean;
}

/**
 * API 使用量信息
 */
export interface ChatCompletionUsage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

/**
 * API 响应体
 */
export interface ChatCompletionResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: ChatCompletionChoice[];
  usage?: ChatCompletionUsage;
}

/**
 * 响应消息
 */
export interface ChatCompletionMessage {
  role: string;
  content: string;
}

/**
 * API 响应选项
 */
export interface ChatCompletionChoice {
  index: number;
  message: ChatCompletionMessage;
  finish_reason: string;
}
