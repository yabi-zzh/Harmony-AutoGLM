/**
 * SSE (Server-Sent Events) 客户端
 * 轻量级实现，用于处理流式 API 响应
 */

import http from '@ohos.net.http';
import util from '@ohos.util';

/**
 * SSE 事件
 */
export interface SSEEvent {
  event?: string;
  data: string;
  id?: string;
}

/**
 * SSE 请求选项
 */
export interface SSERequestOptions {
  url: string;
  method?: http.RequestMethod;
  headers?: Record<string, string>;
  body?: string;
  timeout?: number;
  onMessage?: (data: string) => void;
  onError?: (error: Error) => void;
  onComplete?: () => void;
}

/**
 * SSE 响应块中的 delta 结构
 */
interface SSEDelta {
  content?: string;
  role?: string;
}

/**
 * SSE 响应块中的 choice 结构
 */
interface SSEChoice {
  index?: number;
  delta?: SSEDelta;
  finish_reason?: string;
}

/**
 * SSE 响应块结构
 */
interface SSEChunk {
  id?: string;
  object?: string;
  created?: number;
  model?: string;
  choices?: SSEChoice[];
}

/**
 * SSE 客户端类
 */
export class SSEClient {
  private httpRequest: http.HttpRequest | null = null;
  private buffer: string = '';
  private isConnected: boolean = false;

  /**
   * 发起 SSE 请求
   */
  async request(options: SSERequestOptions): Promise<string> {
    return new Promise((resolve, reject) => {
      this.httpRequest = http.createHttp();
      this.buffer = '';
      this.isConnected = false;
      let fullContent = '';

      const decoder = util.TextDecoder.create('utf-8');

      // 监听流式数据
      this.httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        try {
          const text = decoder.decodeToString(new Uint8Array(data));
          this.buffer += text;

          // 按行解析
          const lines = this.buffer.split('\n');
          this.buffer = lines.pop() || '';

          for (const line of lines) {
            const trimmedLine = line.trim();

            // 跳过空行和注释
            if (!trimmedLine || trimmedLine.startsWith(':')) {
              continue;
            }

            // 解析 data: 前缀
            if (trimmedLine.startsWith('data:')) {
              const jsonStr = trimmedLine.slice(5).trim();

              // 检查是否结束
              if (jsonStr === '[DONE]') {
                continue;
              }

              try {
                const chunk: SSEChunk = JSON.parse(jsonStr) as SSEChunk;
                const choices = chunk.choices;
                if (choices && choices.length > 0) {
                  const delta = choices[0].delta;
                  if (delta && delta.content) {
                    fullContent += delta.content;
                    if (options.onMessage) {
                      options.onMessage(fullContent);
                    }
                  }
                }
              } catch (parseError) {
                // JSON 解析失败，可能是不完整的数据，忽略
                console.warn(`SSEClient: JSON parse failed: ${jsonStr.substring(0, 100)}`);
              }
            }
          }
        } catch (error) {
          console.error(`SSEClient: dataReceive error - ${error}`);
        }
      });

      // 监听请求结束
      this.httpRequest.on('dataEnd', () => {
        this.isConnected = false;
        if (options.onComplete) {
          options.onComplete();
        }
        this.cleanup();
        resolve(fullContent);
      });

      // 构建请求头
      const headers: Record<string, string> = {
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache'
      };
      // 合并自定义请求头
      if (options.headers) {
        const keys = Object.keys(options.headers);
        for (const key of keys) {
          headers[key] = options.headers[key];
        }
      }

      // 构建请求配置
      const requestConfig: http.HttpRequestOptions = {
        method: options.method || http.RequestMethod.POST,
        header: headers,
        extraData: options.body,
        connectTimeout: 60000,
        readTimeout: options.timeout || 120000
      };

      // 发起流式请求
      this.httpRequest.requestInStream(options.url, requestConfig).then((responseCode) => {
        if (responseCode !== 200) {
          this.cleanup();
          const error = new Error(`HTTP ${responseCode}`);
          if (options.onError) {
            options.onError(error);
          }
          reject(error);
        } else {
          this.isConnected = true;
        }
      }).catch((error: Error) => {
        console.error(`SSEClient: requestInStream error - ${error.message}`);
        this.cleanup();
        if (options.onError) {
          options.onError(error);
        }
        reject(error);
      });
    });
  }

  /**
   * 关闭连接
   */
  close(): void {
    this.cleanup();
  }

  /**
   * 清理资源
   */
  private cleanup(): void {
    if (this.httpRequest) {
      try {
        this.httpRequest.destroy();
      } catch (e) {
        // 忽略销毁错误
      }
      this.httpRequest = null;
    }
    this.isConnected = false;
    this.buffer = '';
  }

  /**
   * 是否已连接
   */
  get connected(): boolean {
    return this.isConnected;
  }
}
