# 影流助手 2.0.1：RELAXIN RootHide 构建修复及注入排查

## 本次同步的 GitHub Actions 构建修复

1. `beerpiss/theos-action@v1` 移除，换为 `git clone --depth 1 --recursive https://github.com/roothide/theos.git`，以及 `git clone --depth 1 https://github.com/theos/sdks.git`。在 Actions runner 中自动选择最高版本的 iPhoneOS SDK 链接至 Theos，设置 `THEOS` 和 PATH。
2. 静态检查不再依赖 `theos-src:` 这句仅在旧 action 中出现的字符串或伪注释，改为核对真实 git clone 指令。
3. 为新旧两种原生长按控制器声明 `dataArray`。
4. 用 `NSClassFromString` + `objc_msgSend` 安全地分发原生面板 manager 的实例和 dismiss selector，避免对私有类作链接期强引用。
5. `CommentInputContainerView` Hook 进入专用 `%group DYYYCommentInputContainerViewGroup`，避免与主文件 `%init;` 的默认组重复初始化。
6. 链接选项新增 `-Wl,-undefined,dynamic_lookup`；**注意此参数只让链接期容忍未解析符号，不保证运行时能够加载**，CI 在 `otool -L` 输出依赖供检查。
7. 预处理 `DYYY.xm` Logos 源码，再执行 clean + package，严格只产出一个 RootHide DEB。

## 使用说明

GitHub 仓库 `AutoAnswerCall` 的 `awemevision-2.0.0` 分支由你维护；这里提供的是当前对话附件源码的修正版，**未从该仓库读取或覆盖你已修改的在线文件**。如 GitHub 分支已经包含这些修复，应优先比较差异，避免将新版源码覆盖最新的 GitHub 内容。

GitHub Actions 主工作流默认生成完整版；`Run workflow` 手动运行时可将 `probe_only=true` 打开，生成仅包含注入标记的独立诊断 DEB。**诊断包没有任何正常插件功能**，必须与正式包区分，不要作为正式版发布。

## CI 成功但不注入：诊断次序

- 确认已安装的实际 DEB 来自成功的 GitHub Actions run（下载对应 Artifact，校验 SHA256），不能只看 `success` 状态。
- 在 RELAXIN White List 中允许抖音注入。确认抖音 app bundle ID 为 `com.ss.iphone.ugc.Aweme` 且可执行文件名 `Aweme`（如果重签/分身后名称变化，应按设备实际值修改过滤器）。
- 完全结束抖音进程后再启动；确认没有旧版 DYYY 注入冲突。
- **先安装 probe_only 版**：如果 `AwemeVision-injection-2.0.1.txt` 标记或 `[AWEMEVISION-INJECT]` 日志不存在，优先排查白名单、过滤器、注入框架、依赖和启动崩溃，不应继续修改 UI Hook。
- 如果 probe 版可加载而完整版不可加载，排查完整版强符号依赖（`otool -L`、`nm -u`）、启动崩溃日志和各 Logos `%ctor` 的初始化。`dynamic_lookup` 不等于运行时依赖已满足。
- 如果完整版可加载但设置入口没出现，才继续排查抖音 40.8.0 私有类名及 Hook 是否还匹配。

**本环境没有 Theos / iOS SDK，无法在这里真正编译 DEB 和验证注入。你报告的 CI run 40607467453 success 说明你自己的仓库某个提交已能在 Actions 编译，但并不证明本次附件经过了 CI，也不能证明设备已注入。**
