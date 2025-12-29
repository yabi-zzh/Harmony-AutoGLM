/**
 * AI 模型客户端
 * 负责调用 VLM API（兼容 OpenAI 格式）
 */

import http from '@ohos.net.http';
import {
  ChatCompletionResponse,
  ContentArray,
  ImageContent,
  ImageUrlInfo,
  Message,
  ModelResponse,
  TextContent
} from '../types/ModelTypes';
import { DEFAULT_MODEL_CONFIG, ModelConfig } from '../../models';
import { ActionParser } from '../parser/ActionParser';
import { SSEClient } from './SSEClient';

/**
 * 模型客户端错误
 */
export class ModelClientError extends Error {
  code: string;

  constructor(message: string, code: string = 'UNKNOWN_ERROR') {
    super(message);
    this.name = 'ModelClientError';
    this.code = code;
  }
}

/**
 * 带错误码的错误接口（用于鸿蒙 BusinessError）
 */
interface ErrorWithCode extends Error {
  code?: number | string;
}

/**
 * 模型客户端类
 */
export class ModelClient {
  private config: Required<ModelConfig>;

  constructor(config: ModelConfig) {
    // 验证必填参数
    if (!config.baseUrl || config.baseUrl.trim() === '') {
      throw new ModelClientError('baseUrl 不能为空', 'INVALID_CONFIG');
    }
    if (!config.apiKey || config.apiKey.trim() === '') {
      throw new ModelClientError('apiKey 不能为空', 'INVALID_CONFIG');
    }
    if (!config.modelName || config.modelName.trim() === '') {
      throw new ModelClientError('modelName 不能为空', 'INVALID_CONFIG');
    }

    // 合并默认配置
    this.config = {
      baseUrl: config.baseUrl,
      apiKey: config.apiKey,
      modelName: config.modelName,
      maxTokens: config.maxTokens ?? DEFAULT_MODEL_CONFIG.maxTokens!,
      temperature: config.temperature ?? DEFAULT_MODEL_CONFIG.temperature!,
      topP: config.topP ?? DEFAULT_MODEL_CONFIG.topP!,
      frequencyPenalty: config.frequencyPenalty ?? DEFAULT_MODEL_CONFIG.frequencyPenalty!,
      timeout: config.timeout ?? DEFAULT_MODEL_CONFIG.timeout!
    };
  }

  /**
   * 发送请求到 VLM API
   * @param messages 消息列表
   * @returns 模型响应
   */
  async request(messages: Message[]): Promise<ModelResponse> {
    const startTime = Date.now();

    // 检查是否包含图片
    let hasImage = false;
    for (const msg of messages) {
      if (Array.isArray(msg.content)) {
        for (const item of msg.content) {
          if (item.type === 'image_url') {
            hasImage = true;
            break;
          }
        }
      }
      if (hasImage) break;
    }

    // 构建请求体 - 适配 AutoGLM-Phone API
    interface RequestBody {
      model: string;
      messages: Message[];
      max_tokens: number;
      temperature: number;
      top_p: number;
      frequency_penalty: number;
      stream: boolean;
    }
    
    const requestBody: RequestBody = {
      model: this.config.modelName,
      messages: messages,
      max_tokens: this.config.maxTokens,
      temperature: this.config.temperature,
      top_p: this.config.topP,
      frequency_penalty: this.config.frequencyPenalty,
      stream: false
    };

    // 构建 API URL
    const apiUrl = this.buildApiUrl();
    
    // 计算请求体大小（用于调试）
    const requestBodyStr = JSON.stringify(requestBody);
    const requestBodySize = requestBodyStr.length;
    const messageCount = messages.length;
    
    console.info(`ModelClient: Request - url=${apiUrl}, messages=${messageCount}, hasImage=${hasImage}, bodySize=${requestBodySize}`);
    console.info(`ModelClient: Request params - model=${this.config.modelName}, max_tokens=${this.config.maxTokens}, temperature=${this.config.temperature}, top_p=${this.config.topP}, frequency_penalty=${this.config.frequencyPenalty}, stream=false`);

    try {
      // 创建 HTTP 请求
      const httpRequest = http.createHttp();

      const response = await httpRequest.request(apiUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${this.config.apiKey}`,
          'Accept': 'application/json',
          'Connection': 'keep-alive'
        },
        extraData: requestBodyStr,
        connectTimeout: 60000,  // 连接超时 60 秒
        readTimeout: this.config.timeout  // 读取超时使用配置值
      });

      console.info(`ModelClient: Response received, code=${response.responseCode}`);
      httpRequest.destroy();

      // 检查响应状态
      if (response.responseCode !== 200) {
        const errorBody = typeof response.result === 'string'
          ? response.result
          : JSON.stringify(response.result);
        console.error(`ModelClient: API Error - ${response.responseCode}`);
        throw new ModelClientError(
          `API 请求失败: ${response.responseCode} - ${errorBody}`,
          'API_ERROR'
        );
      }

      // 解析响应
      const responseData: ChatCompletionResponse = typeof response.result === 'string'
        ? JSON.parse(response.result)
        : response.result as ChatCompletionResponse;

      if (!responseData.choices || responseData.choices.length === 0) {
        throw new ModelClientError('API 响应中没有 choices', 'INVALID_RESPONSE');
      }

      const content = responseData.choices[0].message.content;
      const totalTime = Date.now() - startTime;
      console.info(`ModelClient: Completed in ${totalTime}ms`);
      
      // 日志：打印响应内容（截取前500字符）
      const contentPreview = content.length > 500 ? content.substring(0, 500) + '...' : content;
      console.info(`ModelClient: Response content=\n${contentPreview}`);
      
      // 打印 token 使用情况
      if (responseData.usage) {
        console.info(`ModelClient: Token usage - prompt=${responseData.usage.prompt_tokens}, completion=${responseData.usage.completion_tokens}, total=${responseData.usage.total_tokens}`);
      }

      // 解析响应内容
      const parsed = ActionParser.parseResponse(content);
      console.info(`ModelClient: Parsed thinking="${parsed.thinking.substring(0, 100)}..."`);
      console.info(`ModelClient: Parsed actionRaw="${parsed.actionRaw.substring(0, 100)}..."`);

      return {
        thinking: parsed.thinking,
        actionRaw: parsed.actionRaw,
        totalTime: totalTime
      };

    } catch (error) {
      if (error instanceof ModelClientError) {
        throw error;
      }

      // 处理网络错误 - 详细记录错误信息
      let errorMessage: string = '';
      let errorCode: string = '';
      
      if (error instanceof Error) {
        errorMessage = error.message;
        // 尝试获取错误码 - 鸿蒙的 BusinessError 有 code 属性
        const errWithCode = error as ErrorWithCode;
        if (errWithCode.code !== undefined) {
          errorCode = String(errWithCode.code);
        }
      } else if (typeof error === 'object' && error !== null) {
        // 尝试获取对象的详细信息
        try {
          errorMessage = JSON.stringify(error);
          // 尝试从对象中提取 code
          const errObj = error as ErrorWithCode;
          if (errObj.code !== undefined) {
            errorCode = String(errObj.code);
          }
        } catch (e) {
          errorMessage = 'Unknown error object';
        }
      } else {
        errorMessage = String(error);
      }
      
      console.error(`ModelClient: Error - ${errorCode}: ${errorMessage}`);

      if (errorMessage.includes('timeout') || errorMessage.includes('Timeout') || errorCode === '2300028') {
        throw new ModelClientError('请求超时', 'TIMEOUT');
      }

      if (errorMessage.includes('network') || errorMessage.includes('NETWORK') || 
          errorCode === '2300006' || errorCode === '2300007') {
        throw new ModelClientError('网络连接失败', 'NETWORK_ERROR');
      }

      throw new ModelClientError(`请求失败: code=${errorCode}, ${errorMessage}`, 'REQUEST_ERROR');
    }
  }

  /**
   * 构建 API URL
   */
  private buildApiUrl(): string {
    let baseUrl = this.config.baseUrl;

    // 移除末尾的斜杠
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.slice(0, -1);
    }

    // 如果 baseUrl 已经包含 /chat/completions，直接返回
    if (baseUrl.endsWith('/chat/completions')) {
      return baseUrl;
    }

    // 如果 baseUrl 以 /v1 结尾，添加 /chat/completions
    if (baseUrl.endsWith('/v1')) {
      return `${baseUrl}/chat/completions`;
    }

    // 否则添加完整路径
    return `${baseUrl}/chat/completions`;
  }

  /**
   * 流式请求 VLM API
   * @param messages 消息列表
   * @param onChunk 收到内容块时的回调（参数为累积的完整内容）
   * @returns 模型响应
   */
  async requestStream(
    messages: Message[],
    onChunk?: (content: string) => void
  ): Promise<ModelResponse> {
    const startTime = Date.now();

    // 检查是否包含图片，并统计各部分大小
    let hasImage = false;
    let imageSize = 0;
    let textSize = 0;
    for (const msg of messages) {
      if (Array.isArray(msg.content)) {
        for (const item of msg.content) {
          if (item.type === 'image_url') {
            hasImage = true;
            const imgItem = item as ImageContent;
            imageSize += imgItem.image_url.url.length;
          } else if (item.type === 'text') {
            const txtItem = item as TextContent;
            textSize += txtItem.text.length;
          }
        }
      } else if (typeof msg.content === 'string') {
        textSize += msg.content.length;
      }
    }

    // 构建请求体 - 适配 AutoGLM-Phone API
    interface StreamRequestBody {
      model: string;
      messages: Message[];
      max_tokens: number;
      temperature: number;
      top_p: number;
      frequency_penalty: number;
      stream: boolean;
    }

    const requestBody: StreamRequestBody = {
      model: this.config.modelName,
      messages: messages,
      max_tokens: this.config.maxTokens,
      temperature: this.config.temperature,
      top_p: this.config.topP,
      frequency_penalty: this.config.frequencyPenalty,
      stream: true
    };

    const apiUrl = this.buildApiUrl();
    const requestBodyStr = JSON.stringify(requestBody);

    console.info(`ModelClient: Stream body detail - imageSize=${imageSize}, textSize=${textSize}, otherSize=${requestBodyStr.length - imageSize - textSize}`);

    try {
      const sseClient = new SSEClient();

      const sseHeaders: Record<string, string> = {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': `Bearer ${this.config.apiKey}`
      };

      const fullContent = await sseClient.request({
        url: apiUrl,
        headers: sseHeaders,
        body: requestBodyStr,
        timeout: this.config.timeout,
        onMessage: onChunk
      });

      const totalTime = Date.now() - startTime;
      console.info(`ModelClient: Stream completed in ${totalTime}ms`);
      // 日志：打印完整的模型响应内容
      console.info(`ModelClient: fullContent=\n${fullContent}`);

      // 解析完整响应
      const parsed = ActionParser.parseResponse(fullContent);

      return {
        thinking: parsed.thinking,
        actionRaw: parsed.actionRaw,
        totalTime: totalTime
      };

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);

      if (errorMessage.includes('timeout') || errorMessage.includes('Timeout')) {
        throw new ModelClientError('请求超时', 'TIMEOUT');
      }

      throw new ModelClientError(`流式请求失败: ${errorMessage}`, 'STREAM_ERROR');
    }
  }

  /**
   * 获取当前配置
   */
  getConfig(): Required<ModelConfig> {
    const configCopy: Required<ModelConfig> = {
      baseUrl: this.config.baseUrl,
      apiKey: this.config.apiKey,
      modelName: this.config.modelName,
      maxTokens: this.config.maxTokens,
      temperature: this.config.temperature,
      topP: this.config.topP,
      frequencyPenalty: this.config.frequencyPenalty,
      timeout: this.config.timeout
    };
    return configCopy;
  }

  /**
   * 创建用户消息（包含图片和文本）
   * 注意：与 Android 版本保持一致，content 始终为数组格式
   * @param text 文本内容
   * @param imageBase64 可选的 base64 编码图片
   * @returns 消息对象
   */
  static createUserMessage(text: string, imageBase64?: string): Message {
    const content: ContentArray = [];
    
    // 与 Android 版本一致：先放图片，再放文本
    if (imageBase64) {
      const imageUrlInfo: ImageUrlInfo = {
        url: `data:image/jpeg;base64,${imageBase64}`
      };
      const imageContent: ImageContent = {
        type: 'image_url',
        image_url: imageUrlInfo
      };
      content.push(imageContent);
    }
    
    const textContent: TextContent = {
      type: 'text',
      text: text
    };
    content.push(textContent);

    const msg: Message = {
      role: 'user',
      content: content
    };
    return msg;
  }

  /**
   * 创建系统消息
   * @param content 消息内容
   * @returns 消息对象
   */
  static createSystemMessage(content: string): Message {
    const textContent: TextContent = {
      type: 'text',
      text: content
    };
    const msg: Message = {
      role: 'system',
      content: [textContent]
    };
    return msg;
  }

  /**
   * 创建助手消息
   * 注意：与官方实现一致，assistant 消息的 content 使用字符串格式
   * @param content 消息内容
   * @returns 消息对象
   */
  static createAssistantMessage(content: string): Message {
    const msg: Message = {
      role: 'assistant',
      content: content
    };
    return msg;
  }
}
