/**
 * UITest TCP 客户端
 * 通过 TCP 协议连接 UITest 守护进程，实现高效的设备控制
 */

import { socket } from '@kit.NetworkKit';
import { HdcClient } from 'hdclib';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { wifiManager } from '@kit.ConnectivityKit';

const TAG = 'UITestClient';
const DOMAIN = 0x0000;

/** 协议常量 */
const MESSAGE_HEAD = '_uitestkit_rpc_message_head_';
const MESSAGE_TAIL = '_uitestkit_rpc_message_tail_';
const HEAD_LENGTH = 28;
const TAIL_LENGTH = 28;

/** UITest 配置类 */
class UITestConfig {
  static readonly DEVICE_PORT: number = 8012;
  static readonly AGENT_PATH: string = '/data/local/tmp/agent.so';
  static readonly AGENT_RAWFILE: string = 'agent.so';
  static readonly DAEMON_COMMAND: string = 'uitest start-daemon singleness';
  static readonly DAEMON_START_DELAYS: number[] = [30, 50, 80, 100, 150];
  static readonly CONNECT_TIMEOUT: number = 5000;
  static readonly REQUEST_TIMEOUT: number = 10000;
}

/** 初始化阶段 */
export enum InitPhase {
  Idle = 'idle',
  PushingAgent = 'pushing_agent',
  StartingDaemon = 'starting_daemon',
  Connecting = 'connecting',
  Ready = 'ready',
  Error = 'error'
}

/** 连接状态 */
export enum ConnectionState {
  Disconnected = 'disconnected',
  Connecting = 'connecting',
  Connected = 'connected',
  Error = 'error'
}

/** UI 节点边界 */
export interface UINodeBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/** UI 节点信息 */
export interface UINode {
  type: string;
  id?: string;
  text?: string;
  description?: string;
  bounds?: UINodeBounds;
  clickable?: boolean;
  scrollable?: boolean;
  enabled?: boolean;
  focused?: boolean;
  selected?: boolean;
  checked?: boolean;
  children?: UINode[];
}

/** 布局捕获结果 */
export interface LayoutResult {
  success: boolean;
  layout?: UINode;
  error?: string;
}

/** 触控结果 */
export interface TouchResult {
  success: boolean;
  error?: string;
}

/** 解析结果 */
interface ParseResult {
  success: boolean;
  data?: object;
}

/** 设备地址 */
interface DeviceAddress {
  ip: string;
  port: number;
}

/** RPC 请求参数 */
interface RpcArgs {
  x?: number;
  y?: number;
  options?: CaptureOptions;
}

/** Hypium API 请求参数 */
interface HypiumParams {
  api: string;
  this: string;
  args: HypiumArg[];
  message_type: string;
}

/** Hypium 参数类型 */
type HypiumArg = InputTextCoord | string;

/** Hypium RPC 请求 */
interface HypiumRequest {
  module: string;
  method: string;
  params: HypiumParams;
  request_id: string;
  call: string;
  client: string;
}

/** 屏幕尺寸结果 */
export interface DisplaySizeResult {
  success: boolean;
  width?: number;
  height?: number;
  displayId?: number;
  error?: string;
}

/** 屏幕旋转结果 */
export interface DisplayRotationResult {
  success: boolean;
  rotation?: number;  // 0=竖屏, 1=横屏左, 2=竖屏倒置, 3=横屏右
  error?: string;
}

/** 按键结果 */
export interface KeyResult {
  success: boolean;
  error?: string;
}

/** 输入文本结果 */
export interface InputTextResult {
  success: boolean;
  error?: string;
}

/** 屏幕尺寸响应结果 */
interface DisplaySizeResponse {
  displayId: number;
  x: number;
  y: number;
}

/** 输入文本坐标参数 */
interface InputTextCoord {
  x: number;
  y: number;
}

/** 输入文本参数 */
interface InputTextArg {
  coord: InputTextCoord;
  text: string;
}

/** 截图选项 */
interface CaptureOptions {
  displayId: number;
  scale: number;
}

/** RPC 请求参数包装 */
interface RpcParams {
  api: string;
  args: RpcArgs;
}

/** RPC 请求 */
interface RpcRequest {
  module: string;
  method: string;
  params: RpcParams;
}

/** RPC 响应 */
interface RpcResponse {
  result?: UINode | DisplaySizeResponse | number;
}


/**
 * UITest TCP 客户端
 */
export class UITestClient {
  private tcpSocket: socket.TCPSocket | null = null;
  private connId?: string;
  private context?: common.Context;
  private state: ConnectionState = ConnectionState.Disconnected;
  private initPhase: InitPhase = InitPhase.Idle;
  private receiveBuffer: ArrayBuffer = new ArrayBuffer(0);
  private pendingResolve: ((value: object) => void) | null = null;
  private pendingReject: ((reason: Error) => void) | null = null;
  private requestTimeout: number | null = null;
  private onPhaseChange?: (phase: InitPhase, message: string) => void;
  private isRemoteDevice: boolean = false;  // 是否连接远程设备
  private forwardSetup: boolean = false;    // 端口转发是否已设置
  private localForwardPort: number = 0;     // 动态分配的本地转发端口
  private deviceIP: string = '';            // 设备 IP 地址

  constructor(connId?: string, context?: common.Context) {
    this.connId = connId;
    this.context = context;
    // 提取设备 IP
    this.deviceIP = this.extractIPFromConnId(connId);
    // isRemoteDevice 会在 connect() 时通过 checkIsRemoteDevice() 确定
    this.isRemoteDevice = false;
  }

  /**
   * 从 connId 中提取 IP 地址
   */
  private extractIPFromConnId(connId?: string): string {
    if (!connId || connId === '') {
      return '127.0.0.1';
    }
    // connId 格式为 "ip:port"
    const colonIndex = connId.lastIndexOf(':');
    if (colonIndex > 0) {
      return connId.substring(0, colonIndex);
    }
    return connId;
  }

  /**
   * 获取本机 IP 地址（通过 WiFi）
   */
  private getLocalIP(): string {
    try {
      const ipAddress = wifiManager.getIpInfo().ipAddress;
      if (ipAddress === 0) {
        return '';
      }
      // 转换为常用 IP 格式
      const ip = (ipAddress >>> 24) + '.' + (ipAddress >> 16 & 0xFF) + '.' +
                 (ipAddress >> 8 & 0xFF) + '.' + (ipAddress & 0xFF);
      hilog.info(DOMAIN, TAG, `Local WiFi IP: ${ip}`);
      return ip;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `Failed to get WiFi IP: ${e}`);
      return '';
    }
  }

  /**
   * 检查是否为远程设备（设备 IP 不在本机 IP 列表中）
   */
  private checkIsRemoteDevice(): boolean {
    // 没有 connId 说明是本地设备
    if (!this.connId || this.connId === '') {
      return false;
    }

    // 快速检查常见的本地地址
    if (this.deviceIP === '127.0.0.1' || this.deviceIP === 'localhost') {
      hilog.info(DOMAIN, TAG, `Device IP ${this.deviceIP} is loopback, treating as local device`);
      return false;
    }

    // 获取本机 WiFi IP 并对比
    const localIP = this.getLocalIP();
    if (localIP !== '' && this.deviceIP === localIP) {
      hilog.info(DOMAIN, TAG, `Device IP ${this.deviceIP} matches local IP, treating as local device`);
      return false;
    }

    hilog.info(DOMAIN, TAG, `Device IP ${this.deviceIP} is remote device`);
    return true;
  }

  /**
   * 设置阶段变化回调
   */
  setOnPhaseChange(callback: (phase: InitPhase, message: string) => void): void {
    this.onPhaseChange = callback;
  }

  /**
   * 获取连接状态
   */
  getState(): ConnectionState {
    return this.state;
  }

  /**
   * 获取初始化阶段
   */
  getInitPhase(): InitPhase {
    return this.initPhase;
  }

  /**
   * 获取连接 ID
   */
  getConnId(): string {
    return this.connId || '';
  }

  /**
   * 更新阶段并通知
   */
  private updatePhase(phase: InitPhase, message: string): void {
    this.initPhase = phase;
    if (this.onPhaseChange) {
      this.onPhaseChange(phase, message);
    }
  }

  /**
   * 初始化连接
   */
  async connect(): Promise<boolean> {
    if (this.state === ConnectionState.Connected) {
      return true;
    }

    this.state = ConnectionState.Connecting;

    try {
      // 0. 检查是否为远程设备（对比本机 IP）
      this.isRemoteDevice = this.checkIsRemoteDevice();
      hilog.info(DOMAIN, TAG, `Device ${this.deviceIP} isRemoteDevice: ${this.isRemoteDevice}`);

      // 1. 推送 agent.so
      this.updatePhase(InitPhase.PushingAgent, '正在推送 agent.so...');
      const pushResult = await this.pushAgentSo();
      if (!pushResult) {
        throw new Error('推送 agent.so 失败');
      }

      // 2. 启动 UITest 守护进程
      this.updatePhase(InitPhase.StartingDaemon, '正在启动 UITest 守护进程...');
      const daemonStarted = await this.startDaemon();
      if (!daemonStarted) {
        throw new Error('启动 UITest 守护进程失败');
      }

      // 3. 如果是远程设备，设置端口转发
      if (this.isRemoteDevice) {
        this.updatePhase(InitPhase.Connecting, '正在设置端口转发...');
        const forwardResult = await this.setupPortForward();
        if (!forwardResult) {
          throw new Error('端口转发设置失败');
        }
      }

      // 4. 建立 TCP 连接
      this.updatePhase(InitPhase.Connecting, '正在建立 TCP 连接...');
      await this.createTcpConnection();

      this.state = ConnectionState.Connected;
      this.updatePhase(InitPhase.Ready, 'UITest 连接成功');
      return true;

    } catch (error) {
      this.state = ConnectionState.Error;
      this.updatePhase(InitPhase.Error, `连接失败: ${error}`);
      await this.cleanup();
      return false;
    }
  }

  /**
   * 断开连接
   */
  async disconnect(): Promise<void> {
    await this.cleanup();
    this.state = ConnectionState.Disconnected;
  }

  /**
   * 捕获 UI 布局
   */
  async captureLayout(): Promise<LayoutResult> {
    if (this.state !== ConnectionState.Connected) {
      const result: LayoutResult = { success: false, error: '未连接' };
      return result;
    }

    try {
      const emptyArgs: RpcArgs = {};
      const params: RpcParams = {
        api: 'captureLayout',
        args: emptyArgs
      };
      const request: RpcRequest = {
        module: 'com.ohos.devicetest.hypiumApiHelper',
        method: 'Captures',
        params: params
      };

      const response = await this.sendRequest(request) as RpcResponse;
      if (response && response.result) {
        const result: LayoutResult = {
          success: true,
          layout: response.result as UINode
        };
        return result;
      }
      const errorResult: LayoutResult = { success: false, error: '响应格式错误' };
      return errorResult;

    } catch (error) {
      const result: LayoutResult = { success: false, error: `捕获布局失败: ${error}` };
      return result;
    }
  }

  /**
   * 触摸按下
   */
  async touchDown(x: number, y: number): Promise<TouchResult> {
    return this.sendTouchEvent('touchDown', x, y);
  }

  /**
   * 触摸移动
   */
  async touchMove(x: number, y: number): Promise<TouchResult> {
    return this.sendTouchEvent('touchMove', x, y);
  }

  /**
   * 触摸抬起
   */
  async touchUp(x: number, y: number): Promise<TouchResult> {
    return this.sendTouchEvent('touchUp', x, y);
  }

  /**
   * 点击（按下+抬起）
   */
  async tap(x: number, y: number): Promise<TouchResult> {
    const downResult = await this.touchDown(x, y);
    if (!downResult.success) {
      return downResult;
    }
    await this.sleep(50);
    return this.touchUp(x, y);
  }

  /**
   * 滑动
   */
  async swipe(startX: number, startY: number, endX: number, endY: number, duration: number = 500): Promise<TouchResult> {
    const steps = Math.max(Math.floor(duration / 16), 10);
    const deltaX = (endX - startX) / steps;
    const deltaY = (endY - startY) / steps;

    let result = await this.touchDown(startX, startY);
    if (!result.success) return result;

    for (let i = 1; i <= steps; i++) {
      const x = Math.round(startX + deltaX * i);
      const y = Math.round(startY + deltaY * i);
      result = await this.touchMove(x, y);
      if (!result.success) return result;
      await this.sleep(16);
    }

    return this.touchUp(endX, endY);
  }

  /**
   * 长按
   */
  async longPress(x: number, y: number, duration: number = 3000): Promise<TouchResult> {
    const downResult = await this.touchDown(x, y);
    if (!downResult.success) {
      return downResult;
    }
    await this.sleep(duration);
    return this.touchUp(x, y);
  }

  /**
   * 双击
   */
  async doubleTap(x: number, y: number): Promise<TouchResult> {
    const firstTap = await this.tap(x, y);
    if (!firstTap.success) {
      return firstTap;
    }
    await this.sleep(100);
    return this.tap(x, y);
  }

  /**
   * 拖拽（长按后移动到目标位置）
   */
  async drag(startX: number, startY: number, endX: number, endY: number, duration: number = 1000): Promise<TouchResult> {
    // 先按下
    let result = await this.touchDown(startX, startY);
    if (!result.success) return result;

    // 等待触发长按（1秒）
    await this.sleep(2000);

    // 缓慢移动到目标位置
    const steps = Math.max(Math.floor(duration / 16), 20);
    const deltaX = (endX - startX) / steps;
    const deltaY = (endY - startY) / steps;

    for (let i = 1; i <= steps; i++) {
      const x = Math.round(startX + deltaX * i);
      const y = Math.round(startY + deltaY * i);
      result = await this.touchMove(x, y);
      if (!result.success) return result;
      await this.sleep(16);
    }

    // 释放
    return this.touchUp(endX, endY);
  }

  /**
   * 绘制路径（写字、画图等）
   * @param path 路径点数组 [[x1,y1], [x2,y2], ...]
   * @param stepDelay 每步延迟（毫秒）
   */
  async draw(path: [number, number][], stepDelay: number = 10): Promise<TouchResult> {
    if (path.length < 2) {
      return { success: false, error: '路径至少需要2个点' };
    }

    // 按下起点
    let result = await this.touchDown(path[0][0], path[0][1]);
    if (!result.success) return result;

    // 沿路径移动
    for (let i = 1; i < path.length; i++) {
      result = await this.touchMove(path[i][0], path[i][1]);
      if (!result.success) return result;
      await this.sleep(stepDelay);
    }

    // 抬起
    const lastPoint = path[path.length - 1];
    return this.touchUp(lastPoint[0], lastPoint[1]);
  }

  /**
   * 捏合缩小（模拟双指向内捏合）
   * 注意：这是单指模拟，实际效果可能有限
   */
  async pinchIn(centerX: number, centerY: number, distance: number = 200): Promise<TouchResult> {
    // 从外向内滑动模拟缩小
    const startOffset = distance;
    const endOffset = distance / 4;

    return this.swipe(
      centerX - startOffset, centerY,
      centerX - endOffset, centerY,
      300
    );
  }

  /**
   * 捏合放大（模拟双指向外张开）
   * 注意：这是单指模拟，实际效果可能有限
   */
  async pinchOut(centerX: number, centerY: number, distance: number = 200): Promise<TouchResult> {
    // 从内向外滑动模拟放大
    const startOffset = distance / 4;
    const endOffset = distance;

    return this.swipe(
      centerX - startOffset, centerY,
      centerX - endOffset, centerY,
      300
    );
  }

  /**
   * 按下返回键
   */
  async pressBack(): Promise<KeyResult> {
    return this.sendHypiumRequest('Driver.pressBack', []);
  }

  /**
   * 按下 Home 键
   */
  async pressHome(): Promise<KeyResult> {
    return this.sendHypiumRequest('Driver.pressHome', []);
  }

  /**
   * 获取屏幕尺寸
   */
  async getDisplaySize(): Promise<DisplaySizeResult> {
    if (this.state !== ConnectionState.Connected) {
      return { success: false, error: '未连接' };
    }

    try {
      const response = await this.sendHypiumRequestRaw('Driver.getDisplaySize', []);
      if (response && response.result) {
        const displayResult = response.result as DisplaySizeResponse;
        return {
          success: true,
          width: displayResult.x,
          height: displayResult.y,
          displayId: displayResult.displayId
        };
      }
      return { success: false, error: '响应格式错误' };
    } catch (error) {
      return { success: false, error: `获取屏幕尺寸失败: ${error}` };
    }
  }

  /**
   * 输入文本
   */
  async inputText(text: string, x: number = 0, y: number = 0): Promise<InputTextResult> {
    const coord: InputTextCoord = { x, y };
    return this.sendHypiumRequest('Driver.inputText', [coord, text]);
  }

  /**
   * 获取屏幕旋转方向
   * @returns rotation: 0=竖屏, 1=横屏左, 2=竖屏倒置, 3=横屏右
   */
  async getDisplayRotation(): Promise<DisplayRotationResult> {
    if (this.state !== ConnectionState.Connected) {
      return { success: false, error: '未连接' };
    }

    try {
      const response = await this.sendHypiumRequestRaw('Driver.getDisplayRotation', []);
      if (response && response.result !== undefined) {
        const rotation = response.result as number;
        return {
          success: true,
          rotation: rotation
        };
      }
      return { success: false, error: '响应格式错误' };
    } catch (error) {
      return { success: false, error: `获取屏幕旋转方向失败: ${error}` };
    }
  }


  // ==================== 私有方法 ====================

  /**
   * 生成请求 ID
   */
  private generateRequestId(): string {
    const now = new Date();
    const timestamp = now.getFullYear().toString() +
      (now.getMonth() + 1).toString().padStart(2, '0') +
      now.getDate().toString().padStart(2, '0') +
      now.getHours().toString().padStart(2, '0') +
      now.getMinutes().toString().padStart(2, '0') +
      now.getSeconds().toString().padStart(2, '0') +
      now.getMilliseconds().toString().padStart(3, '0') +
      Math.floor(Math.random() * 1000).toString().padStart(3, '0');
    return timestamp;
  }

  /**
   * 发送 Hypium API 请求
   */
  private async sendHypiumRequest(api: string, args: HypiumArg[]): Promise<KeyResult> {
    if (this.state !== ConnectionState.Connected) {
      return { success: false, error: '未连接' };
    }

    try {
      await this.sendHypiumRequestRaw(api, args);
      return { success: true };
    } catch (error) {
      return { success: false, error: `${api} 失败: ${error}` };
    }
  }

  /**
   * 发送 Hypium API 请求并返回原始响应
   */
  private async sendHypiumRequestRaw(api: string, args: HypiumArg[]): Promise<RpcResponse> {
    if (this.state !== ConnectionState.Connected) {
      throw new Error('未连接');
    }

    const request: HypiumRequest = {
      module: 'com.ohos.devicetest.hypiumApiHelper',
      method: 'callHypiumApi',
      params: {
        api: api,
        this: 'Driver#0',
        args: args,
        message_type: 'hypium'
      },
      request_id: this.generateRequestId(),
      call: 'xdevice',
      client: '127.0.0.1'
    };

    const response = await this.sendRequestGeneric(request) as RpcResponse;
    return response;
  }

  /**
   * 推送 agent.so 到设备
   */
  private async pushAgentSo(): Promise<boolean> {
    if (!this.context) {
      return true;
    }

    try {
      // 检查设备上的文件是否存在
      const checkResult = HdcClient.shell(
        `test -f "${UITestConfig.AGENT_PATH}" && echo "EXISTS" || echo "NOT_EXISTS"`,
        this.connId
      );

      if (checkResult.success && checkResult.output.includes('EXISTS')) {
        return true;
      }

      // 从 rawfile 读取 agent.so
      const resourceManager = this.context.resourceManager;
      const agentData = await resourceManager.getRawFileContent(UITestConfig.AGENT_RAWFILE);

      // 使用 filesDir 而不是 cacheDir（权限问题）
      const tempPath = `${this.context.filesDir}/agent.so`;
      const file = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, agentData.buffer as ArrayBuffer);
      fileIo.closeSync(file);

      // 推送到设备
      const sendResult = HdcClient.fileSend(tempPath, UITestConfig.AGENT_PATH, this.connId);
      if (sendResult !== 0) {
        hilog.error(DOMAIN, TAG, `Push agent.so failed: ${sendResult}`);
        try { fileIo.unlinkSync(tempPath); } catch (e) {}
        return false;
      }

      // 删除临时文件
      try { fileIo.unlinkSync(tempPath); } catch (e) {}
      return true;

    } catch (error) {
      hilog.error(DOMAIN, TAG, `Push agent.so error: ${error}`);
      return false;
    }
  }

  /**
   * 发送触摸事件
   */
  private async sendTouchEvent(api: string, x: number, y: number): Promise<TouchResult> {
    if (this.state !== ConnectionState.Connected) {
      const result: TouchResult = { success: false, error: '未连接' };
      return result;
    }

    try {
      const args: RpcArgs = { x: Math.round(x), y: Math.round(y) };
      const params: RpcParams = {
        api: api,
        args: args
      };
      const request: RpcRequest = {
        module: 'com.ohos.devicetest.hypiumApiHelper',
        method: 'Gestures',
        params: params
      };

      await this.sendRequest(request);
      const result: TouchResult = { success: true };
      return result;

    } catch (error) {
      const result: TouchResult = { success: false, error: `触摸事件失败: ${error}` };
      return result;
    }
  }

  /**
   * 启动 UITest 守护进程
   */
  private async startDaemon(): Promise<boolean> {
    const psResult = HdcClient.shell('ps -ef | grep uitest', this.connId);
    if (psResult.success) {
      const lines = psResult.output.split('\n');
      for (const line of lines) {
        // 检查是否是纯净的 uitest start-daemon singleness 进程
        // 排除带 --extension-name 的进程（如 scrcpy_server）
        if (line.includes('uitest') && line.includes('start-daemon') &&
            line.includes('singleness') && !line.includes('grep') &&
            !line.includes('--extension-name')) {
          return true;
        }
      }
    }

    HdcClient.shell(UITestConfig.DAEMON_COMMAND, this.connId);

    for (const delay of UITestConfig.DAEMON_START_DELAYS) {
      await this.sleep(delay);
      const checkResult = HdcClient.shell('ps -ef | grep uitest', this.connId);
      if (checkResult.success) {
        const lines = checkResult.output.split('\n');
        for (const line of lines) {
          // 同样排除带 --extension-name 的进程
          if (line.includes('start-daemon singleness') && !line.includes('grep') &&
              !line.includes('--extension-name')) {
            return true;
          }
        }
      }
    }

    hilog.error(DOMAIN, TAG, 'Daemon start timeout');
    return false;
  }


  /**
   * 创建 TCP 连接
   */
  private async createTcpConnection(): Promise<void> {
    this.tcpSocket = socket.constructTCPSocketInstance();

    this.tcpSocket.on('message', (value: socket.SocketMessageInfo) => {
      this.onDataReceived(value.message);
    });

    this.tcpSocket.on('error', (err: Error) => {
      hilog.error(DOMAIN, TAG, `Socket error: ${err.message}`);
      this.state = ConnectionState.Error;
      if (this.pendingReject) {
        try {
          this.pendingReject(err);
        } catch (e) {
          // ignore
        }
        this.clearPending();
      }
    });

    this.tcpSocket.on('close', () => {
      this.state = ConnectionState.Disconnected;
    });

    // 解析设备地址（格式: ip:port 或 ip）
    const deviceAddress = this.parseDeviceAddress();
    hilog.info(DOMAIN, TAG, `Connecting to ${deviceAddress.ip}:${deviceAddress.port}`);

    const address: socket.NetAddress = {
      address: deviceAddress.ip,
      port: deviceAddress.port,
      family: 1
    };
    const connectOptions: socket.TCPConnectOptions = {
      address: address,
      timeout: UITestConfig.CONNECT_TIMEOUT
    };

    try {
      await this.tcpSocket.connect(connectOptions);
      hilog.info(DOMAIN, TAG, `TCP connected to ${deviceAddress.ip}:${deviceAddress.port}`);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : JSON.stringify(error);
      hilog.error(DOMAIN, TAG, `TCP connect failed to ${deviceAddress.ip}:${deviceAddress.port}: ${errorMsg}`);
      throw new Error(`TCP 连接失败: ${errorMsg}`);
    }
  }

  /**
   * 解析设备地址
   */
  private parseDeviceAddress(): DeviceAddress {
    if (this.isRemoteDevice) {
      // 远程设备：通过端口转发连接
      // HDC forward 在本地监听端口，转发到远程设备
      // 所以连接本地 127.0.0.1 + 转发端口
      return {
        ip: '127.0.0.1',
        port: this.localForwardPort
      };
    }
    // 本机设备：直接连接 127.0.0.1:8012（不需要转发）
    return {
      ip: '127.0.0.1',
      port: UITestConfig.DEVICE_PORT
    };
  }

  /**
   * 获取系统分配的可用端口
   * 通过绑定端口 0，让系统自动分配一个未占用的端口
   */
  private async getAvailablePort(): Promise<number> {
    return new Promise((resolve, reject) => {
      const tempSocket = socket.constructTCPSocketInstance();

      const address: socket.NetAddress = {
        address: '127.0.0.1',
        port: 0,  // 端口 0 表示让系统自动分配
        family: 1
      };

      tempSocket.bind(address).then(() => {
        // 获取实际绑定的端口
        tempSocket.getLocalAddress().then((localAddr: socket.NetAddress) => {
          const port = localAddr.port !== undefined ? localAddr.port : 0;
          if (port === 0) {
            tempSocket.close();
            reject(new Error('系统分配端口失败'));
            return;
          }
          // 关闭临时 socket，释放端口
          tempSocket.close().then(() => {
            hilog.info(DOMAIN, TAG, `Got available port: ${port}`);
            resolve(port);
          }).catch(() => {
            resolve(port);  // 即使关闭失败也返回端口
          });
        }).catch((err: Error) => {
          tempSocket.close();
          reject(new Error(`获取本地地址失败: ${err.message}`));
        });
      }).catch((err: Error) => {
        reject(new Error(`绑定端口失败: ${err.message}`));
      });
    });
  }

  /**
   * 设置端口转发（远程设备需要）
   * 动态分配本地端口，避免多设备冲突
   */
  private async setupPortForward(): Promise<boolean> {
    if (!this.isRemoteDevice) {
      return true;
    }

    try {
      // 获取系统分配的可用端口
      const availablePort = await this.getAvailablePort();

      const localPort = `tcp:${availablePort}`;
      const remotePort = `tcp:${UITestConfig.DEVICE_PORT}`;

      hilog.info(DOMAIN, TAG, `Setting up port forward: ${localPort} -> ${remotePort}`);

      const result = await HdcClient.forward(localPort, remotePort, this.connId);
      if (result === 0) {
        this.localForwardPort = availablePort;
        this.forwardSetup = true;
        hilog.info(DOMAIN, TAG, `Port forward command sent successfully on port ${availablePort}`);

        // 等待端口转发生效
        await this.sleep(500);

        // 查询当前端口转发列表
        const listResult = HdcClient.forwardList(this.connId);
        hilog.info(DOMAIN, TAG, `forwardList result: success=${listResult.success}, output=${listResult.output}`);

        return true;
      } else {
        hilog.error(DOMAIN, TAG, `Port forward failed with code: ${result}`);
        return false;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Port forward error: ${error}`);
      return false;
    }
  }

  /**
   * 移除端口转发
   */
  private removePortForward(): void {
    if (this.forwardSetup && this.localForwardPort > 0) {
      try {
        // 使用 HdcClient.forwardRemove 清理端口转发
        // 对应命令: hdc fport rm tcp:localPort tcp:remotePort
        const localPort = `tcp:${this.localForwardPort}`;
        const remotePort = `tcp:${UITestConfig.DEVICE_PORT}`;
        hilog.info(DOMAIN, TAG, `Removing port forward: ${localPort} -> ${remotePort}`);
        
        const result = HdcClient.forwardRemove(localPort, remotePort, this.connId || '');
        hilog.info(DOMAIN, TAG, `Remove port forward result: ${result}`);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `Remove port forward error: ${e}`);
      }
      
      this.forwardSetup = false;
      this.localForwardPort = 0;
    }
  }

  /**
   * 发送请求并等待响应
   */
  private sendRequest(jsonData: RpcRequest): Promise<object> {
    return this.sendRequestGeneric(jsonData);
  }

  /**
   * 发送通用请求并等待响应
   */
  private sendRequestGeneric(jsonData: object): Promise<object> {
    return new Promise((resolve, reject) => {
      if (!this.tcpSocket) {
        reject(new Error('Socket 未初始化'));
        return;
      }

      if (this.state !== ConnectionState.Connected) {
        reject(new Error('未连接'));
        return;
      }

      this.pendingResolve = resolve;
      this.pendingReject = reject;
      this.receiveBuffer = new ArrayBuffer(0);

      this.requestTimeout = setTimeout(() => {
        if (this.pendingReject) {
          this.pendingReject(new Error('请求超时'));
          this.clearPending();
        }
      }, UITestConfig.REQUEST_TIMEOUT) as number;

      const packet = this.buildRequestPacketGeneric(jsonData);

      const sendOptions: socket.TCPSendOptions = { data: packet.buffer as ArrayBuffer };
      this.tcpSocket.send(sendOptions)
        .catch((err: Error) => {
          hilog.error(DOMAIN, TAG, `Send failed: ${err.message}`);
          if (this.pendingReject) {
            this.pendingReject(err);
            this.clearPending();
          }
        });
    });
  }

  /**
   * 构建请求包
   */
  private buildRequestPacket(jsonData: RpcRequest): Uint8Array {
    return this.buildRequestPacketGeneric(jsonData);
  }

  /**
   * 构建通用请求包
   */
  private buildRequestPacketGeneric(jsonData: object): Uint8Array {
    const jsonString = JSON.stringify(jsonData);
    const textEncoder = new util.TextEncoder();
    const jsonBytes = textEncoder.encodeInto(jsonString);

    const sessionId = Math.floor(Math.random() * 0xFFFFFFFF);
    const headBytes = textEncoder.encodeInto(MESSAGE_HEAD);
    const tailBytes = textEncoder.encodeInto(MESSAGE_TAIL);

    const totalLength = HEAD_LENGTH + 4 + 4 + jsonBytes.length + TAIL_LENGTH;
    const packet = new Uint8Array(totalLength);
    let offset = 0;

    packet.set(headBytes, offset);
    offset += HEAD_LENGTH;

    packet[offset++] = (sessionId >> 24) & 0xFF;
    packet[offset++] = (sessionId >> 16) & 0xFF;
    packet[offset++] = (sessionId >> 8) & 0xFF;
    packet[offset++] = sessionId & 0xFF;

    const length = jsonBytes.length;
    packet[offset++] = (length >> 24) & 0xFF;
    packet[offset++] = (length >> 16) & 0xFF;
    packet[offset++] = (length >> 8) & 0xFF;
    packet[offset++] = length & 0xFF;

    packet.set(jsonBytes, offset);
    offset += jsonBytes.length;

    packet.set(tailBytes, offset);

    return packet;
  }

  /**
   * 处理接收到的数据
   */
  private onDataReceived(data: ArrayBuffer): void {
    this.receiveBuffer = this.concatArrayBuffer(this.receiveBuffer, data);

    const result = this.parseResponse();
    if (result.success && this.pendingResolve && result.data) {
      this.pendingResolve(result.data);
      this.clearPending();
    }
  }

  /**
   * 解析响应包
   */
  private parseResponse(): ParseResult {
    const MIN_LENGTH = HEAD_LENGTH + 4 + 4 + TAIL_LENGTH;
    const bufferView = new Uint8Array(this.receiveBuffer);

    if (bufferView.length < MIN_LENGTH) {
      const result: ParseResult = { success: false };
      return result;
    }

    const textEncoder = new util.TextEncoder();
    const headBytes = textEncoder.encodeInto(MESSAGE_HEAD);
    for (let i = 0; i < HEAD_LENGTH; i++) {
      if (bufferView[i] !== headBytes[i]) {
        const result: ParseResult = { success: false };
        return result;
      }
    }

    let offset = HEAD_LENGTH;
    offset += 4;

    const dataLength = (bufferView[offset] << 24) |
                       (bufferView[offset + 1] << 16) |
                       (bufferView[offset + 2] << 8) |
                       bufferView[offset + 3];
    offset += 4;

    const totalLength = HEAD_LENGTH + 4 + 4 + dataLength + TAIL_LENGTH;
    if (bufferView.length < totalLength) {
      const result: ParseResult = { success: false };
      return result;
    }

    const jsonBytes = bufferView.slice(offset, offset + dataLength);
    offset += dataLength;

    const tailBytes = textEncoder.encodeInto(MESSAGE_TAIL);
    for (let i = 0; i < TAIL_LENGTH; i++) {
      if (bufferView[offset + i] !== tailBytes[i]) {
        const result: ParseResult = { success: false };
        return result;
      }
    }

    const textDecoder = util.TextDecoder.create('utf-8');
    const jsonString = textDecoder.decodeToString(jsonBytes);
    const data = JSON.parse(jsonString) as object;

    const result: ParseResult = { success: true, data: data };
    return result;
  }

  /**
   * 合并 ArrayBuffer
   */
  private concatArrayBuffer(buf1: ArrayBuffer, buf2: ArrayBuffer): ArrayBuffer {
    const result = new Uint8Array(buf1.byteLength + buf2.byteLength);
    result.set(new Uint8Array(buf1), 0);
    result.set(new Uint8Array(buf2), buf1.byteLength);
    return result.buffer as ArrayBuffer;
  }

  /**
   * 清理 pending 状态
   */
  private clearPending(): void {
    if (this.requestTimeout !== null) {
      clearTimeout(this.requestTimeout);
      this.requestTimeout = null;
    }
    this.pendingResolve = null;
    this.pendingReject = null;
  }

  /**
   * 清理资源
   */
  private async cleanup(): Promise<void> {
    this.clearPending();

    if (this.tcpSocket) {
      try {
        this.tcpSocket.off('message');
        this.tcpSocket.off('error');
        this.tcpSocket.off('close');
        await this.tcpSocket.close();
      } catch (e) {
        // 忽略关闭错误
      }
      this.tcpSocket = null;
    }

    // 移除端口转发
    this.removePortForward();
  }

  /**
   * 延迟
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
