# v30 · OpenAI 对话版

启动 `Summer The Cat AI.app`。菜单栏入口为「夏天 AI」。

## 连接

1. 打开猫咪对话框，点击右上角齿轮，或从菜单选择「AI 连接设置…」，服务商选择 OpenAI。
2. 在原生安全输入框填写自己的 OpenAI API Key，可使用 Command+V 或「粘贴密钥」按钮。
3. 选择模型，点击「保存」。默认模型为 `gpt-6-luna`，也可以填写自己项目可用的模型 ID。
4. 可先点击「验证对话」，发送一条简短测试消息，验证实际生成权限及额度；会使用项目 API 额度。
5. 回到对话框输入文字，按 Enter 或点击发送。

密钥已保存时，设置里的密钥输入框仍为空；留空保存会保留已有密钥。点击「移除密钥」只删除本机保存的凭据。

## 对话与动作

- 回复逐段显示，发送按钮在请求期间变为「停止」。
- 支持中文输入法、Shift + Enter 换行、失败重试、开始新对话。
- 保留最多 12 轮完整对话，实际请求再按文本长度限制上下文。失败和停止的回复不会加入后续上下文。
- 当前动作先完整播放，再进入歪头；等待模型期间维持呼吸循环。回复完成或停止后，在动画边界退出并回正。
- 关闭对话框会停止正在进行的请求；重新打开仍保留本次窗口的聊天内容。
- 当前支持文字对话。没有加入语音、联网搜索、文件访问或操作电脑的工具。

## 凭据和消息

API Key 保存在 macOS 钥匙串，服务名为 `local.summerthecat.v30.openai`。网页只知道是否已配置，不会读取到密钥。

原生程序通过 HTTPS 请求 `https://api.openai.com/v1/responses`，发送当前问题及本次会话中选取的上下文。聊天记录只保留在运行中的内存，不写入本机磁盘。请求设置 `store: false`；这不代表免除 OpenAI 服务端的数据处理政策。

独立打开 `source/chat.html` 或 `对话框预览.html` 用于界面预览；模型连接设置与请求由应用里的原生模块处理。

## 文件

- `Summer The Cat AI.app`：OpenAI 版应用，Apple Silicon / Intel 通用。
- `SummerTheCat-v30-OpenAI-macOS.zip`：OpenAI 版应用压缩包。
- `SummerTheCat-v30-OpenAI-source.zip`：当前源码与素材。
- `source/OpenAIClient.swift`：Responses API、流式解析、钥匙串及上下文组装。
- `source/OpenAISettingsUI.swift`：原生连接设置与模型访问验证。
- `source/ConversationUI.swift`：请求生命周期、界面事件及动画衔接。

执行 `zsh source/build.sh` 构建 AI 版。原 UI 版 `Summer The Cat.app` 可单独打开。

## 已验证的范围

`OpenAI客户端验证.json` 使用本地 URLProtocol 模拟响应，检查实际原生请求逻辑、中文 UTF-8 分块、流式完成、取消、错误处理、上下文限制和钥匙串存取。

`OpenAI界面验证.json` 检查中文输入法、流式显示、停止、重试、新对话及文本渲染。

`OpenAI原生验证/conversation-checks.json` 检查 macOS 应用中当前动作完成后进入歪头、呼吸循环、排队回正。

以上自动检查不使用真实 API Key，也不代表已验证具体项目的线上调用。填写有效密钥后，可在应用中发送一句话进行实际确认。

接口依据：[OpenAI Responses API 文本生成](https://developers.openai.com/api/docs/guides/text)、[流式响应](https://developers.openai.com/api/docs/guides/streaming-responses)、[模型目录](https://developers.openai.com/api/docs/models)。

## 2.0.30.2 粘贴修复

已补齐 macOS 标准编辑菜单和 Command+V 等快捷键，并增加原生「粘贴密钥」按钮。更新后请退出正在运行的旧版，再打开此目录中的 AI 版应用。修复与测试未读取或改写用户剪贴板。

## 2.0.30.3 错误诊断修复

流式错误现显示服务返回的错误码、说明、模型和请求编号，并对凭据做脱敏。「验证对话」使用真实短消息，替代只读取模型信息的检查。

本次对 gpt-4.1-mini 的实际接口诊断返回 `credit_balance_exhausted`，即 API 无剩余额度。需在 OpenAI Platform 账单页添加 API 额度后重试；本次尚未获得成功生成结果。诊断不输出密钥或用户聊天内容。
