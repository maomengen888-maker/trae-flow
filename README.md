# 简屿 · 灵动岛

<p align="center">
  <img src="TraeFlow/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="简屿 · 灵动岛图标">
</p>

<p align="center">
  <b>Mac 顶部的个人工作台与 AI 陪伴助手。</b><br>
  待办、随笔、需求资料和日常工具集中在一座岛里。
</p>

<p align="center">
  macOS 14+ · Swift / SwiftUI · Apache 2.0
</p>

项目目前处于个人开发与体验阶段。应用名称仍为 `灵动岛.app`，源码中的 `TraeFlow`、`Dynamic` 名称保留用于兼容。

## 当前功能

### 今日工作台

- **四列待办**：待处理、进行中、等待中、已完成；支持拖动任务、优先级和截止时间提醒。
- **Markdown 随笔**：创建、搜索、重命名、编辑和归档，保存为本地文件。
- **需求管理**：按「需求 PRD → 原型文档 → 测试验收 → 上线」组织阶段，每项需求自动建立独立目录，导入资料时复制到对应阶段。
- **天气**：自动定位或手动设置城市，展示天气、降雨概率与带伞建议。
- **录音与音乐**：快速录音、语音转写，并将文字转为待办或随笔；显示系统正在播放的音乐并提供播放控制。
- **截图置顶**：`Control + Shift + S` 调起系统截图工具，支持区域、窗口、全屏截图和置顶查看。

工作台中的「AI 今日建议」目前根据待办与天气生成规则提示；完整模型对话通过 AI 入口使用。

### AI 陪伴与记忆

AI 入口打开原生陪伴工作区，提供陪伴、复盘、建议、知识问答四种模式，以及历史会话、记忆管理、资料库和模型调用记录。

- **可管理的记忆**：根据「我叫」「我喜欢」「我的目标」「记住」等明确表达提取信息，保留来源、确认状态和冲突提示；可确认、修改、删除或添加禁止记忆规则。部分明确表达会自动确认。
- **本地资料库**：导入文本、Markdown、可提取文字的 PDF 等文件，按当前问题检索片段并显示参考来源。单个文件上限 50 MB；扫描件 PDF 暂无 OCR，无法提取文字的文件仅保留原件与元数据。
- **隐私空间**：使用 Touch ID 解锁，私密条目以 AES-GCM 加密，密钥保存在 macOS 钥匙串。该空间不参与当前的对话上下文检索；无可用生物识别的设备目前无法解锁。
- **模型连接**：支持 Dify、DeepSeek、OpenAI 和兼容 Chat Completions 的服务，需自行填写 API 地址、模型与 API Key。模型可用性取决于对应服务。
- **调用记录**：记录服务商、模型、时间、耗时、结果状态与输入字符数，不在此记录中保存对话正文或 API Key。

记忆提取与资料检索目前采用本地规则和文本匹配。使用远程模型时，对话及自动选入的记忆、资料片段会发送给所配置的服务商；“本地保存”不表示模型推理离线运行。

### 抖音与悬浮小窗

主面板内嵌抖音网页，也可打开可移动、置顶的独立小窗。关闭或切换离开相关面板时暂停媒体。网页登录、内容与可用性由第三方网站决定。

### 开发者工作台与 TRAE 集成

AI 侧栏中的「开发者工作台」保留 DeepSeek Harness 入口，首次使用通过 `npx` 下载并启动 `@deepseek-ai/dsh`，在本机 `127.0.0.1:3080` 嵌入 Web UI。Harness 的工作区、模型和工具权限由其自身管理。

项目也保留 TRAE、TRAE CN、TRAE WORK、TRAE WORK CN 的 Hook 会话状态、跳回编辑器、桌面宠物与自定义功能区域等基础能力。

## 环境与运行

- macOS 14 或更高版本。
- 从源码构建需要 Xcode，以及支持 Swift 6.1 的工具链（构建内置 Bridge 和运行 Prototype 测试使用）。
- Node.js 与 `npx` 仅用于可选的 DeepSeek Harness。
- AI 远程服务、天气和内嵌网页需要网络；服务账号和调用费用由相应提供方管理。

```bash
git clone https://github.com/maomengen888-maker/trae-flow.git
cd trae-flow
open TraeFlow.xcodeproj
```

在 Xcode 中选择 `TraeFlow` Scheme 和 `My Mac` 后运行。Bundle ID 为 `ai.dynamic.app`。

也可在仓库根目录构建：

```bash
xcodebuild \
  -project TraeFlow.xcodeproj \
  -scheme TraeFlow \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

首次构建可能需要下载 Swift Package 依赖。运行时按实际使用功能授予定位、麦克风、语音识别、通知或系统控制权限。

## 数据与隐私

- 需求文档、随笔、录音、截图和工作台索引保存在桌面的 `灵动岛` 文件夹。
- 「立即备份」备份工作台、需求索引及提醒数据，不是全部附件、录音、AI 数据或钥匙串的完整备份。
- AI 记忆、资料索引与非 Dify 会话历史保存在本机运行目录；这些普通数据文件未使用隐私空间的加密机制。Dify 历史会话由所配置的 Dify 服务管理。
- API Key 保存在本机权限为 `0600` 的凭据文件中，不写入仓库。请勿将密钥、个人数据或诊断中的敏感内容提交到 GitHub。
- 录音保存在本地；转写使用 Apple Speech 框架，当前未强制设备端识别，不能保证全程离线。
- 截图默认保存在本机，只有点击上传操作后才发送到图床服务。

详细数据流见 [隐私说明](docs/privacy-policy.md)。

## 开发与验证

[2026-09-28 验证记录](docs/verification-2026-09-28.md)：Debug 构建通过；定向单元测试 48 项通过、21 项失败，失败集中在 `NotchViewModelTests`，仍待处理。

```bash
# Prototype 逻辑与进程/Socket 测试
swift test --package-path Prototype

# 主应用单元测试
xcodebuild -project TraeFlow.xcodeproj -scheme TraeFlow \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  test -only-testing:TraeFlowTests

# 完整回归（含 UI 测试）
./scripts/test.sh
```

UI 测试的执行可能需要可用的本机签名与 macOS 权限。发行流程及其当前限制见 [发布说明](docs/sparkle-release.md)；从源码构建不等同于已签名、公证的发行包。

主要代码：`TraeFlow/` 为应用，`Prototype/` 为 SwiftPM Bridge 与测试，`TraeFlow/Services/Dynamic/` 为工作台和陪伴服务，`TraeFlow/UI/Views/DynamicAIAgentView.swift` 为 AI 界面。

## 项目背景与参与

简屿 · 灵动岛基于 [ccsonicc333/trae-flow](https://github.com/ccsonicc333/trae-flow) 继续设计与开发，在原项目的 Mac 灵动岛、TRAE 会话状态和自定义区域基础上，扩展个人工作台与 AI 陪伴功能。感谢原作者和开源贡献者。

欢迎通过 [Issues](https://github.com/maomengen888-maker/trae-flow/issues) 提交问题与建议，通过 Pull Request 改进功能、文档和测试。报告问题时请附上 macOS 版本、复现步骤，并移除密钥和个人信息。

## License

[Apache License 2.0](LICENSE.md)
