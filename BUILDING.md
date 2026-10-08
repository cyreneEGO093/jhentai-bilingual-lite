# 可复现构建说明

源代码基础：JHenTai `1e23251d5efd4d93b0cacfe0f08b5a25fa3c7e31`。
使用 Flutter **3.44.8**（框架提交 `058e0af2c2b57e369d905a03ac9748b0ebf543c6`）及其 Dart **3.12.2**。
该 SDK 的引擎源码版本为 `0cd610717bde95fd88343c64f81c11ba4e5c0010`，引擎构建产物标识为 `13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939`。
固定版本 SDK 源码：[Flutter 框架与内置 Dart 工具](https://github.com/flutter/flutter/tree/058e0af2c2b57e369d905a03ac9748b0ebf543c6)，[Flutter 引擎源码](https://github.com/flutter/flutter/tree/0cd610717bde95fd88343c64f81c11ba4e5c0010/engine)。引擎的 `DEPS` 指定其 Dart 与原生第三方源代码版本；SDK/编译工具不随应用源码 ZIP 打包。

请保留 `pubspec.lock`，不要使用 `pub upgrade`。不需要任何站点账号、模型 API Key 或上游私有 API 签名密钥来编译。

## 准备

将源码放在较短的本地路径，例如 `E:\src\jhentai`。Windows 插件的 C++ 头文件路径可能超过传统路径限制，长路径环境下仅开启 Git longpaths 不足以解决。

安装 Git 和指定版本 Flutter。Windows 需要 Visual Studio 2022 的 C++ 桌面构建工具、CMake、Windows SDK，以及可选组件「C++ ATL for latest v143 build tools (x86 & x64)」（`Microsoft.VisualStudio.Component.VC.ATL`，系统密钥存储插件需要）。Android 需要 JDK 17、Android SDK Platform 36、Build Tools 36.0.0 和 NDK 28.2.13676358。部分上游插件还会自动下载较早的 SDK Platform / Build Tools。仓库的 Wrapper 配置固定 Gradle 8.14，AGP 为 8.11.1；Flutter 准备项目时会生成未随源码分发的 Wrapper 启动文件。

```text
flutter doctor -v
flutter pub get
flutter test test/translation
```

如使用代理，请在自己的构建环境配置代理，勿把账号或代理密码写入源码。依赖下载需要访问 pub.dev、GitHub、Google/Android 与 Maven 仓库。

## Windows x64

```text
flutter build windows -t lib/src/main.dart --release
```

输出为 `build/windows/x64/runner/Release/`。分发时保留整个目录的 EXE、DLL 和 data，并附上 LICENSE、NOTICE、LICENSES 及对应源码包。若目标系统缺少 VC++ 运行库，需要安装微软官方 x64 Visual C++ Redistributable。

## Android

调试构建（用于模拟器，自动使用本机调试签名）：

```text
flutter build apk -t lib/src/main.dart --debug --target-platform android-x64
```

正式构建前自行创建签名密钥，并在被 Git 忽略的 `android/key.properties` 中填写 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。不要把该文件或 keystore 打包进源码。

```text
flutter build apk -t lib/src/main.dart --release --split-per-abi --target-platform android-arm64
```

输出位于 `build/app/outputs/flutter-apk/`。普通 Android 手机通常使用 arm64-v8a 包。独立应用 ID 为 `io.github.cyreneego093.jhentai.bilingual`；同一衍生版的后续更新需使用同一签名证书。签名与 ZIP 时间戳可导致字节差异，不影响从同一源码复现功能。

## 原生集成测试

测试使用程序生成的图片和设备内回环 HTTP 模拟 API，不消耗真实 API 额度，不访问真实漫画站点。

```text
flutter test integration_test/translation_smoke_test.dart -d windows
flutter devices
flutter test integration_test/translation_smoke_test.dart -d <Android设备ID>
```

覆盖系统密钥存储、设置保存与连接验证、读取现有图片、整图/框选、缩放映射、跨图片共用工具栏、未浏览图片的批量翻译、取消与错误隔离、连续拖动缩放、评论预览布局和双语文本。测试结束后恢复原翻译设置。建议用独立测试安装运行，避免与正在阅读的实例并行访问应用数据。

切换源码绝对路径后，应在没有其他构建运行时执行 `flutter clean` 和 `flutter pub get`。同一目录的 Windows/Android 构建请依次执行，以避免共享生成文件发生冲突。

**测试后构建正式包时不要添加 `--no-pub`。** 固定版本的 Flutter 会在正常构建准备阶段重新生成插件注册文件，并移除仅用于开发的 `integration_test` 插件；`--no-pub` 会跳过这一步，可能留下测试注册项，导致 Android Release 编译失败或 Windows 包携带测试插件。无需手工编辑生成文件，也不要把集成测试插件移入生产依赖。

## 打包

完成测试后，使用 Python 3.10 或更高版本收集本次解析到的依赖源码和许可证，再打包两个平台。输出目录应在工程目录之外：

如修改 Android 依赖，先在 `android/` 内运行 `gradlew -I ../tool/android_dependency_inventory.gradle :app:bilingualDependencyReport -Ptarget-platform=android-arm64`（Windows 使用 `gradlew.bat`），再回到工程根目录执行 `python tool/collect_android_notices.py --gradle-cache <本机 GRADLE_USER_HOME>`。审核新清单后重新构建，让许可资产进入 APK。现有源码包已包含本版本的许可清单。

```text
python tool/collect_licenses.py --sources ../release/dependency-sources.zip
python tool/package_release.py --output ../release --android-apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

先创建 `../release` 目录。应用源码包保留 Git 跟踪的文件及未忽略的新文件；排除本机缓存、签名文件、账号配置和测试输出，并检查常见密钥格式。`SHA256SUMS.txt` 记录所有交付包的哈希。不要把自己填写的配置或签名密钥加入 Git。

发行时同时提供 `android-dependency-sources.zip`（`tool/fetch_android_sources.py --cache <本机缓存> --archive <目标ZIP>`）和 `native-source-supplement.zip`。后者保存插件实际使用的 SQLite C 源码、下载地址及哈希；其版本应与 Windows CMake 和 Android Maven 清单一致。Flutter SDK/引擎版本见本文开头；依赖源码归档中的 BUILDING.md 和 pubspec.lock 也应与本次应用源码一致。
