# JHenTai · 双语轻译（非官方衍生版）

在 JHenTai 的原生 Flutter 阅读器中加入 Bilingual Lite 的 BYOK 漫画与文本翻译。
优先支持 Windows x64 和 Android；不需要在应用内安装浏览器扩展，也不依赖 Python/ONNX OCR 服务。

**这是个人自用的实验项目。本衍生版的开发与改动完全由 GPT-6 Astra 通过 vibe coding 完成，不对可靠性、翻译准确性以及后期维护作任何保证。**

上游 JHenTai 与第三方代码保留原作者署名和许可证；上述声明仅指本衍生版新增及修改部分。
项目不隶属于 JHenTai 上游维护者、OpenRouter 或模型供应商。请勿把衍生版的问题提交给上游作者。

源码：[cyreneEGO093/jhentai-bilingual-lite](https://github.com/cyreneEGO093/jhentai-bilingual-lite) · [下载安装包与对应源码](https://github.com/cyreneEGO093/jhentai-bilingual-lite/releases)

## 使用

1. 打开应用设置中的 **双语轻译 · BYOK**，填写 API 地址、自己的 API Key、文本模型、图片模型和目标语言。
2. 默认地址为 OpenRouter 的 OpenAI 兼容 API。图片模型必须支持视觉输入，模型名称和能力由所选服务商决定。
3. 阅读器界面共用一个可拖动的「译」工具栏。选择 **整图** 翻译当前图片，**框选** 翻译选区；**整页翻译** 会逐张翻译当前作品的全部图片，包括尚未浏览的图片。工具栏显示当前操作的图片编号，并可切换前后图片。
4. 「原图／译文」切换当前图片的遮罩；进入「调整」后点选并直接拖动译文框，或拖动工具栏中的 **移动／缩放** 按钮连续调整。桌面还支持拖动右下角手柄和 Shift+拖动缩放；手机不在气泡文字上显示操作按钮。**重置框位** 恢复模型返回的位置与大小。
5. 作品标题和评论下的「翻译文本」会追加译文，保留原内容和交互。

工具条可手动拖动，没有内容自动规避。设置可调整不透明度、译文字号、工具条大小，并设置作品背景、术语表和文本／整图／框选提示词。提示词支持 `{{targetLang}}`，留空采用默认值。结构化输出格式由程序追加。

翻译只在用户点击时发起。当前图片优先复用阅读器已解码的图像；批量翻译会复用缓存或通过阅读器原有流程加载尚未浏览的图片。图片在内存中裁切并压缩为 JPEG（质量 85，长边不超过 1280px）。已在阅读器中显示的动态图发送当前帧，批量加载的未显示动态图发送第一帧。译文只做显示覆盖，不修改源文件。

## 费用与限制

- API Key 由用户自行申请和填写。软件没有内置密钥、额度或免费翻译服务。
- 并发最多 2 个请求；`temperature=0.1`、`max_tokens=1500`。OpenRouter 请求显式使用 `reasoning.enabled=false`，其他兼容端点不附加 OpenRouter 专属参数。
- 429 限流最多自动等待重试一次；401、402、截断或无效响应会显示错误，用户可缩小区域重试。模型不支持关闭思考时，应更换模型。
- 单图不保证固定费用；以服务商的模型价格和账单为准。全图定位、专有名词和密集小字仍可能不准确。
- 译文与框位只在当前阅读会话中保存，退出阅读器后清空。整页翻译需用户主动点击，会增加下载流量和 API 用量；逐张处理、可随时停止，保留已完成结果。单图失败继续处理下一张；401/402 会停止队列。再次点击整页翻译只重试尚未完成的图片。

## 安装与构建

Windows 解压完整的 Windows 包后运行 `jhentai_bilingual.exe`，不要只复制 EXE。
Android 安装与设备架构匹配的 APK。衍生版采用独立应用 ID，可与上游版本共存，不会自动迁移上游账号或下载配置。

构建步骤见 [BUILDING.md](BUILDING.md)，隐私说明见 [PRIVACY.bilingual.md](PRIVACY.bilingual.md)。发行页同时提供应用源码、Dart 与 Android 依赖源码、原生源码补充包及许可证归档；构建时请使用对应版本的全部源码包。

Windows x64 与 Android arm64 提供安装包；已进行 Windows 与 Android 模拟器测试，尚未覆盖各品牌实体手机。其他平台没有本衍生版的验证与发行包。

## 来源与许可

- JHenTai：官方仓库 [jiangtian616/JHenTai](https://github.com/jiangtian616/JHenTai)，基础版本 `v8.0.16+334`，原有代码采用 Apache-2.0。
- Bilingual Lite：[cyreneEGO093/bilingual-lite](https://github.com/cyreneEGO093/bilingual-lite)，移植基础为 `v0.6.0`，GPL-3.0-only。
- 本组合衍生版整体按 **GPL-3.0-only** 分发，保留上游 Apache-2.0 及第三方声明；不把上游原始代码的许可改写为仅 GPL。
- 具体提交、修改范围和版权声明见 [NOTICE](NOTICE)，依赖许可副本在 `LICENSES/`，本次分发复核见 [LICENSES/REVIEW.md](LICENSES/REVIEW.md)。
- 上游的 Syncfusion 图表依赖已替换为 Flutter Canvas 图表，避免把需要额外商业或社区许可的组件纳入 GPL 分发。
- 上游 PIN 输入控件附带的 Google Play 短信自动填充依赖已移除，改用 Flutter 原生四位密码输入；本地密码校验和生物识别仍保留。

原版功能介绍与致谢保留在 [README.upstream.md](README.upstream.md) 和 [README.upstream.zh-CN.md](README.upstream.zh-CN.md)。已移除上游应用更新检查、设置开关和更新弹窗，旧配置无法重新启用。应用不会自动检查、下载或安装新版本；需要更新时，在「关于 → 手动下载本衍生版」打开本仓库发行页。直接安装上游安装包不会包含此翻译模块。
