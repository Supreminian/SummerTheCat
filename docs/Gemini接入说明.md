# v30 · Google Gemini 接口

当前版本为 `2.0.30.4`，支持 Google Gemini 和 OpenAI 两种服务。

## 开始使用

1. 退出正在运行的旧版「夏天 AI」，再打开本目录的 `Summer The Cat AI.app`。
2. 打开猫咪对话框 → 右上角齿轮，或菜单栏「夏天 AI」→「AI 连接设置…」。
3. 服务商选择 **Google Gemini**。
4. 点击「获取密钥 ↗」进入 [Google AI Studio](https://aistudio.google.com/app/apikey)，创建 Gemini API Key。
5. 回到原生设置窗口，使用 Command+V 或「粘贴密钥」按钮填入密钥。不要把密钥填到聊天框中。
6. 模型默认 `gemini-3.5-flash-lite`；可按项目实际可用情况选择其他 Gemini 文本模型。
7. 点击「验证对话」，检查实际文字生成。验证会发送一条简短测试消息，并消耗少量项目配额。
8. 点击「保存」，回到猫咪对话框开始聊天。

Google 官方价格页列有默认模型的免费层；实际可用额度由模型、地区及 Google 项目决定。程序不会替你开通计费或升级套餐。免费额度不足、密钥无效、模型权限和网络错误会显示对应提示。

## 对话行为

- 支持逐段显示文字、多轮上下文、停止、失败重试和开始新对话。
- 猫咪当前动作先完整播放，再歪头进入；等待回复期间维持呼吸循环，完成后排队回正。
- 切换服务商或模型后开始新的对话，不会把旧服务的上下文自动发送给另一家。
- Gemini 与 OpenAI 的模型选择和密钥分开保存，可随时在设置里切换。

## 凭据与接口

Gemini 密钥保存在 macOS 钥匙串的 `local.summerthecat.v30.gemini` 项目中，原有 OpenAI 项目保持独立。网页只接收服务商、模型和是否已配置等状态，不接收密钥。

Gemini 使用 Google 官方原生 `streamGenerateContent` 接口。密钥通过 `x-goog-api-key` 请求头发送，不拼接到 URL。

发送内容包括当前问题、选取的完整对话轮次和猫咪助手的系统说明。聊天记录只保存在当前应用进程内。Google 对免费服务数据的处理以其政策为准。

## 验证范围

- `Gemini客户端验证.json`：通过本地模拟 HTTP/SSE 响应，检查中文流式解析、原生请求格式、鉴权、取消、错误、上下文及旧 OpenAI 接口兼容性。
- `Gemini界面验证.json`：浏览器输入、服务商显示、停止、重试、新对话和输出渲染。
- `Gemini原生验证/`：实际 macOS 设置界面与完整动作队列检查。

自动测试没有使用真实 Gemini 密钥。配置自己的密钥后，请在应用内点击「验证对话」完成账号的线上确认。

构建：`zsh source/build.sh`。当前提供 macOS Apple Silicon / Intel 通用版。

官方依据：[原生生成接口](https://ai.google.dev/api/generate-content)、[API Key](https://ai.google.dev/gemini-api/docs/api-key)、[模型免费层与价格](https://ai.google.dev/gemini-api/docs/pricing)。
