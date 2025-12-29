/**
 * AppConfig - 应用级配置常量
 *
 * 所有应用级别的配置统一在此定义，包括网络配置、Agent配置、UI配置和存储配置。
 * 其他模块通过导入使用配置，不自行定义默认值。
 */

/**
 * 网络配置接口
 */
interface NetworkConfig {
  /** 默认超时时间（毫秒） */
  defaultTimeout: number;
  /** 最大重试次数 */
  maxRetries: number;
  /** 重试间隔（毫秒） */
  retryDelay: number;
}

/**
 * Agent 配置接口
 */
interface AgentConfig {
  /** 最大执行步骤数 */
  maxSteps: number;
  /** 动作间隔（毫秒） */
  actionDelay: number;
  /** 截图重试次数 */
  screenshotRetries: number;
}

/**
 * UI 配置接口
 */
interface UIConfig {
  /** 启动页显示时间（毫秒） */
  splashDuration: number;
  /** 滚动延迟（毫秒） */
  scrollDelay: number;
}

/**
 * 存储配置接口
 */
interface StorageConfig {
  /** Preferences 存储名称 */
  preferencesName: string;
  /** 配置存储键名 */
  configKey: string;
}

/**
 * 应用配置接口
 */
interface AppConfigType {
  network: NetworkConfig;
  agent: AgentConfig;
  ui: UIConfig;
  storage: StorageConfig;
}

/**
 * 网络配置
 */
const networkConfig: NetworkConfig = {
  defaultTimeout: 60000,
  maxRetries: 3,
  retryDelay: 1000
};

/**
 * Agent 配置
 */
const agentConfig: AgentConfig = {
  maxSteps: 15,
  actionDelay: 300,
  screenshotRetries: 3
};

/**
 * UI 配置
 */
const uiConfig: UIConfig = {
  splashDuration: 2000,
  scrollDelay: 100
};

/**
 * 存储配置
 */
const storageConfig: StorageConfig = {
  preferencesName: 'ai_agent_config',
  configKey: 'model_config'
};

/**
 * 应用级配置常量
 */
export const APP_CONFIG: AppConfigType = {
  network: networkConfig,
  agent: agentConfig,
  ui: uiConfig,
  storage: storageConfig
};
