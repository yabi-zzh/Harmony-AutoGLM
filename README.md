# Next AI Agent

基于 AutoGLM 的 HarmonyOS NEXT 智能自动化助手，通过自然语言指令控制手机完成各种任务。

## 功能特性

- **AI 驱动** - 集成 AutoGLM 视觉语言模型，理解屏幕内容并自主决策
- **原生控制** - 基于 HarmonyOS UITest 协议，实现精准的设备操控
- **无线连接** - 通过 HDC 无线调试连接设备，无需数据线
- **自然语言** - 用日常语言描述任务，AI 自动执行

## 系统要求

- HarmonyOS NEXT 5.0.0 (API 12) 及以上
- DevEco Studio 5.0.0 及以上
- 目标设备需开启开发者选项和无线调试

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/yabi-zzh/Harmony-AutoGLM.git
cd Harmony-AutoGLM
```

### 2. 配置 API 密钥

在应用设置页面配置你的 AutoGLM API 密钥：
- API 地址：`https://open.bigmodel.cn/api/paas/v4`
- 模型名称：`autoglm-phone`

### 3. 连接设备

1. 在目标手机上开启「开发者选项」→「无线调试」
2. 记录显示的 IP 地址和端口
3. 在应用中输入 IP 和端口，点击连接
4. 在手机上确认授权弹窗

### 4. 执行任务

连接成功后，进入任务页面，用自然语言描述你想完成的任务，例如：
- "打开微信，发送消息给张三"
- "打开抖音，搜索美食"
- "打开相册，删除最近的照片"

## 项目结构

```
entry/src/main/ets/
├── agent/                 # AI Agent 核心模块
│   ├── client/           # API 客户端
│   ├── core/             # Agent 核心逻辑
│   ├── device/           # 设备控制服务
│   ├── parser/           # 动作解析器
│   ├── storage/          # 配置存储
│   └── types/            # 类型定义
├── models/               # 数据模型
├── pages/                # 页面组件
├── utils/                # 工具类
└── viewmodels/           # 视图模型 (MVVM)
```

## 支持的操作

| 操作 | 说明 |
|------|------|
| Tap | 点击屏幕坐标 |
| Swipe | 滑动手势 |
| Type | 输入文本 |
| Launch | 启动应用 |
| Back | 返回上一页 |
| Home | 回到桌面 |
| Long Press | 长按 |
| Double Tap | 双击 |
| Wait | 等待 |

## 开发

### 构建项目

使用 DevEco Studio 打开项目，同步依赖后即可构建运行。

### 依赖说明

- `hdclib` - HDC 客户端库，用于设备连接和控制

## 注意事项

- 本项目仅供学习和研究使用
- 使用 AI 自动化操作时请注意安全，避免执行敏感操作
- 部分操作（如登录、支付）需要人工介入

## 许可证

[Apache License 2.0](LICENSE)

## 致谢

- [AutoGLM](https://open.bigmodel.cn/) - 智谱 AI 视觉语言模型
- [HarmonyOS](https://developer.huawei.com/) - 华为鸿蒙操作系统
