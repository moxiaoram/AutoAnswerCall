# DYYY 抖音 40.8.0 — 兼容基线源码（实验版）

此项目基于用户提供的 DYYY 完整源码 `DYYY-main`，整合了 `DYYY-抖音40.8.0-兼容修复源码补丁包` 的修复项。

## 做过的源码改动

1. `DYYY.xm`：`UIWindow initWithFrame:`、`initWithWindowScene:` 与 `makeKeyAndVisible` 三条路径安装双指长按设置手势，使用关联对象防重复；关闭手势取消默认视图触摸的行为，减少误拦截。
2. `DYYY.xm`：找到顶层 present 的控制器再打开设置，避免连续弹出设置页。
3. `DYYY.xm`：纯净模式的旧版 `pureMode` 私有 KVC 加异常捕获，防止属性重命名引起 NSUnknownKeyException。
4. `DYYY.xm`：仅找到 Swift 评论输入容器类时才安装相关 Hook。
5. `DYYY408Compatibility.h/.m`：添加本地运行时类/方法检查和可见视图类计数报告，**只在 Bundle ID 为 com.ss.iphone.ugc.Aweme 且版本等于 40.8.0 时执行**；仅写入本地 Caches、不联网；该报告不包含用户文本或账号内容。
6. `Makefile`：纳入新增 `.m`；初始打包版本号与界面版本号设为 `1.1`。原有 RootHide/Rootless 分支保留。
7. `DYYYManager.m`、`DYYYLongPressPanel.xm` 与设置界面：新增「解析下载地址」独立开关，可复制接口返回的直链；`control` 和 `DYYYConstants.h` 升至 `1.2`。

## 重要限制

- **这不是已经在抖音 40.8.0 上全部验证成功的成品**。原始项目仅标注抖音 36.5.0 测试，无法仅靠源代码确认 40.8.0 的私有类/方法仍然匹配。视频操作、评论、直播、功能按钮仍需逐项真机测试。
- 当前环境没有 iOS SDK 与 Theos，**未编译 `.deb`，未测试 RootHide 注入、真机稳定性**。
- 如果使用的是抖音极速版 `com.ss.iphone.ugc.aweme.lite`，插件筛选允许注入，但运行时报告仅对普通版抖音启用，不能以普通版报告推断极速版兼容性。
- 原项目源文件、许可证和配置保持原样，不会自动替换用户的设置数据。

## 编译

安装带对应 iOS SDK 的 Theos 后，在此源码根目录：

```sh
make clean package SCHEME=roothide
```

若你使用 Rootless 环境：

```sh
make clean package SCHEME=rootless
```

先备份原 DYYY 插件与配置，再在可恢复的测试设备上安装。本版本的 `Makefile` 保留原项目的 `after-package` 自动安装分支（`INSTALL=1` 时才触发），不要随意指定 `INSTALL=1`。

## 获取 40.8.0 运行时检查报告

1. 在测试机打开普通版抖音 40.8.0，等待首页加载后再浏览内容；启动约 8 秒时会写入第一次类检查快照。
2. 在抖音 App 的沙盒 Library/Caches 中找到 `DYYY-40.8.0-compat.txt`。可用 Filza 或你的越狱环境有权限的文件工具导出。
3. 用报告中各个 `[present]` / `[missing]` 结果与功能测试结果判断下一批需要 Hook 的类。**即使标记 present，也不能证明对应功能已兼容。**

建议逐项测试：打开 DYYY 设置 → 视频首页/进度条 → 点赞/评论/分享 → 搜索 → 直播；遇到异常请保留具体功能与页面截图或崩溃日志。

## 文件校验

- `DYYY.xm`、`Makefile`、`control` 为原文件局部修改。
- `DYYY408Compatibility.h`、`DYYY408Compatibility.m` 和本说明为新增文件。
- 其他原始项目文件不修改。

## 后续版本号约定

- 插件从 **1.0** 起步；初始名称调整版为 **1.1**，本次功能版升至 **1.2**，后续按 **1.3、1.4……** 依次递增。
- 每次更新同时修改 `control` 的 `Version` 与 `DYYYConstants.h` 的 `DYYY_VERSION`，确保安装包版本与设置界面版本一致。
- **抖音 40.8.0 是目标 App 的版本号，并非本插件版本号**；它的运行时检测条件和报告文件名不得因插件版本递增而修改。
- 1.1 仅调整显示名称、版本与侧边栏入口文本；1.2 新增解析下载地址入口，并未改变原有下载入口。
