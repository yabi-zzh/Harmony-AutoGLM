/**
 * IndexViewModel - Index 页面的 ViewModel
 * 
 * 负责管理 Index 页面的 UI 状态和设备连接业务逻辑。
 * 使用 @Observed 装饰器实现响应式绑定。
 */

import { common } from '@kit.AbilityKit';
import { getErrorMessage, HdcClient, HdcErrorCode } from 'hdclib';
import { DeviceService } from '../agent/device/DeviceService';

@Observed
export class IndexViewModel {
  // UI 状态属性
  ipAddress: string = '192.168.9.108';
  port: string = '45441';
  isConnecting: boolean = false;
  connectionStatus: string = '未连接';
  connectedDevice: string = '';
  errorMessage: string = '';
  isInitialized: boolean = false;
  
  // 设备信息
  deviceName: string = '';
  deviceModel: string = '';
  systemVersion: string = '';
  apiVersion: string = '';
  ohosFullName: string = '';
  cpuAbiList: string = '';
  
  // 设备控制状态
  isControlling: boolean = false;

  // Toast 回调
  onShowToast?: (message: string) => void;

  /**
   * 初始化 ViewModel
   * 从 AppStorage 读取 HDC 初始化状态（由 SplashPage 完成初始化）
   * @param context UIAbilityContext
   */
  initialize(context: common.UIAbilityContext): void {
    // 检查 AppStorage 中是否有已连接设备
    const storedDevice = AppStorage.get<string>('connectedDevice');
    if (storedDevice && storedDevice.length > 0) {
      this.connectedDevice = storedDevice;
      this.connectionStatus = '已连接';
    }

    // 检查 HDC 初始化状态（由 SplashPage 完成）
    const hdcInitialized = AppStorage.get<boolean>('hdcInitialized');
    if (hdcInitialized) {
      this.isInitialized = true;
      // 不再自动调用 listTargets，改为按需调用（用户点击连接时）
    } else {
      const initError = AppStorage.get<string>('hdcInitError');
      this.errorMessage = initError || 'HDC 未初始化';
    }
  }

  /**
   * 检查已连接的设备
   */
  checkConnectedDevices(): void {
    try {
      const targets = HdcClient.listTargets();
      if (targets.count > 0 && targets.devices.length > 0) {
        const device = targets.devices[0];
        if (device.state === 'device') {
          this.connectedDevice = device.connectKey;
          this.connectionStatus = '已连接';
          AppStorage.setOrCreate('connectedDevice', this.connectedDevice);
        }
      } else {
        const storedDevice = AppStorage.get<string>('connectedDevice');
        if (storedDevice) {
          AppStorage.delete('connectedDevice');
          this.connectedDevice = '';
          this.connectionStatus = '未连接';
        }
      }
    } catch (error) {
      // 检查设备失败，忽略
    }
  }

  /**
   * 连接设备
   */
  async connectDevice(): Promise<void> {
    if (!this.ipAddress || !this.port) {
      this.errorMessage = '请输入 IP 地址和端口';
      return;
    }

    this.isConnecting = true;
    this.errorMessage = '';

    try {
      const portNum = parseInt(this.port);
      const result = await HdcClient.connect(this.ipAddress, portNum, 30000);

      switch (result) {
        case HdcErrorCode.SUCCESS:
        this.connectedDevice = `${this.ipAddress}:${this.port}`;
        this.connectionStatus = '已连接';
        AppStorage.setOrCreate('connectedDevice', this.connectedDevice);
        this.fetchDeviceInfo();
        this.showToast('连接成功');
          break;
        case HdcErrorCode.ERR_AUTH_REJECTED:
        this.errorMessage = '用户在设备上拒绝了授权';
        this.connectionStatus = '连接失败';
          break;
        case HdcErrorCode.ERR_AUTH_TIMEOUT:
        this.errorMessage = '等待用户授权超时，请在设备上确认授权弹窗';
        this.connectionStatus = '连接失败';
          break;
        case HdcErrorCode.ERR_CONNECTION_TIMEOUT:
        this.errorMessage = '连接超时，请检查网络连接';
        this.connectionStatus = '连接失败';
          break;
        case HdcErrorCode.ERR_CONNECTION_REFUSED:
        this.errorMessage = '连接被拒绝，请确认设备已开启无线调试';
        this.connectionStatus = '连接失败';
          break;
        default:
        this.errorMessage = `连接失败: ${getErrorMessage(result)}`;
        this.connectionStatus = '连接失败';
      }
    } catch (error) {
      this.errorMessage = `连接异常: ${error}`;
      this.connectionStatus = '连接失败';
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 断开设备连接
   */
  async disconnectDevice(): Promise<void> {
    try {
      // 先关闭 UITest 客户端
      await DeviceService.getInstance().closeUITestClient();

      const result = HdcClient.disconnect();
      if (result === HdcErrorCode.SUCCESS) {
        this.connectedDevice = '';
        this.connectionStatus = '未连接';
        this.clearDeviceInfo();
        AppStorage.delete('connectedDevice');
        this.showToast('已断开连接');
      } else {
        this.errorMessage = `断开失败: ${getErrorMessage(result)}`;
      }
    } catch (error) {
      this.errorMessage = `断开异常: ${error}`;
    }
  }

  /**
   * 清理 HDC 资源
   * 应用退出时调用
   */
  cleanup(): void {
    try {
      HdcClient.cleanup();
      console.info('IndexViewModel: HDC cleanup completed');
    } catch (error) {
      console.error(`IndexViewModel: HDC cleanup error: ${error}`);
    }
  }

  /**
   * 设置 IP 地址
   * @param value IP 地址
   */
  setIpAddress(value: string): void {
    this.ipAddress = value;
  }

  /**
   * 设置端口
   * @param value 端口号
   */
  setPort(value: string): void {
    this.port = value;
  }

  /**
   * 获取设备信息
   */
  fetchDeviceInfo(): void {
    try {
      // 获取设备名称 (如 HUAWEI Mate 60 Pro)
      const nameResult = HdcClient.shell('param get const.product.name', this.connectedDevice);
      if (nameResult.success && nameResult.output && !nameResult.output.includes('fail')) {
        this.deviceName = nameResult.output.trim();
      }
      
      // 获取设备型号 (如 ALN-AL00)
      const modelResult = HdcClient.shell('param get const.product.model', this.connectedDevice);
      if (modelResult.success && modelResult.output && !modelResult.output.includes('fail')) {
        this.deviceModel = modelResult.output.trim();
      }
      
      // 获取 HarmonyOS 版本 (如 6.0.0)
      const versionResult = HdcClient.shell('param get const.product.os.dist.version', this.connectedDevice);
      if (versionResult.success && versionResult.output && !versionResult.output.includes('fail')) {
        this.systemVersion = 'HarmonyOS ' + versionResult.output.trim();
      }
      
      // 获取 API 版本 (如 21)
      const apiResult = HdcClient.shell('param get const.ohos.apiversion', this.connectedDevice);
      if (apiResult.success && apiResult.output && !apiResult.output.includes('fail')) {
        this.apiVersion = apiResult.output.trim();
      }
      
      // 获取 OpenHarmony 完整版本 (如 OpenHarmony-6.0.1.120)
      const fullNameResult = HdcClient.shell('param get const.ohos.fullname', this.connectedDevice);
      if (fullNameResult.success && fullNameResult.output && !fullNameResult.output.includes('fail')) {
        this.ohosFullName = fullNameResult.output.trim();
      }
      
      // 获取 CPU ABI 列表 (如 arm64-v8a)
      const abiResult = HdcClient.shell('param get const.product.cpu.abilist', this.connectedDevice);
      if (abiResult.success && abiResult.output && !abiResult.output.includes('fail')) {
        this.cpuAbiList = abiResult.output.trim();
      }
    } catch (error) {
      console.error(`IndexViewModel: fetchDeviceInfo error: ${error}`);
    }
  }

  /**
   * 清除设备信息
   */
  private clearDeviceInfo(): void {
    this.deviceName = '';
    this.deviceModel = '';
    this.systemVersion = '';
    this.apiVersion = '';
    this.ohosFullName = '';
    this.cpuAbiList = '';
  }

  /**
   * 显示 Toast 消息
   * @param message 消息内容
   */
  private showToast(message: string): void {
    if (this.onShowToast) {
      this.onShowToast(message);
    }
  }

  /**
   * 熄屏
   */
  async screenOff(): Promise<void> {
    if (this.isControlling) return;
    this.isControlling = true;
    try {
      const result = HdcClient.shell('power-shell setmode 602', this.connectedDevice);
      if (result.success) {
        this.showToast('已熄屏');
      } else {
        this.showToast('熄屏失败');
      }
    } catch (error) {
      this.showToast(`熄屏异常: ${error}`);
    } finally {
      this.isControlling = false;
    }
  }

  /**
   * 亮屏解锁
   */
  async wakeUpAndUnlock(): Promise<void> {
    if (this.isControlling) return;
    this.isControlling = true;
    try {
      // 先亮屏
      const wakeResult = HdcClient.shell('power-shell wakeup', this.connectedDevice);
      if (!wakeResult.success) {
        this.showToast('亮屏失败');
        return;
      }
      // 等待屏幕亮起
      await new Promise<void>(resolve => setTimeout(resolve, 500));
      // 上滑解锁
      const unlockResult = HdcClient.shell('uitest uiInput swipe 500 1800 500 800 200', this.connectedDevice);
      if (unlockResult.success) {
        this.showToast('已亮屏解锁');
      } else {
        this.showToast('解锁失败');
      }
    } catch (error) {
      this.showToast(`亮屏解锁异常: ${error}`);
    } finally {
      this.isControlling = false;
    }
  }
}
