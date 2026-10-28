# 影流助手 2.0.0 — 独立插件 / 离线更新策略

## 独立身份
- **插件名**：影流助手（RELAXIN 专用）
- **Debian Package**：`com.local.awemevision.relaxin`（不同于原项目 `com.huami.dyyy`）
- **Tweak 动态库**：`AwemeVision.dylib`；过滤器 `AwemeVision.plist`
- **版本**：`2.0.0`；不会被旧包标识的 apt 更新路径当作升级版本
- **Conflicts: com.huami.dyyy**：禁止同时安装、重复 Hook 导致崩溃。手动先卸载旧版，再安装新版。
- 原作者和许可证信息保留在 LICENSE、README 和历史文档中；本次是独立二次开发，并非原作者发布的新版本。

## 更新检测说明
- 移除原项目 GitHub 远程 ABTest 配置默认地址、后台启动更新请求、手动检查更新按钮、远程模式、远程配置地址设置。
- 保留本地 ABTest 数据导入/导出与补丁覆写/替换；本地图集及配置目录改为 `Documents/AwemeVision/`，不再自动读取旧版 `Documents/DYYY/` 的远程配置缓存。原先远程模式的用户设置值不再触发任何网络下载。
- 「屏蔽抖音应用更新提示」是可选的 *抖音客户端* 提示屏蔽功能，与本插件版本升级无关。
- 本插件不检测最新版本、不连接旧作者的发布源、不自动下载升级包。将来升级只能通过你自行构建并手动安装单独发布的 DEB。
- 用户源中若同时保留旧项目，旧项目可以独立更新，但新版包不是旧包的升级候选；请先卸载旧包。

## RELAXIN 设备目标
- iPhone15,3、iOS 17.3 (21D50)、RELAXIN v0.4.8 / RootHide / 白名单、抖音 40.8.0。
- RootHide Scheme；DEB 元数据 Architecture `iphoneos-arm64e`；dylib 二进制 arm64。
- 启用白名单允许抖音注入，不等于 ABI/Hook 已经通过真机验证。

## GitHub Actions 编译
1. 上传整个项目目录（含隐藏文件 `.github/workflows/build.yml`）至你的 GitHub 仓库。
2. 在 Actions 中运行 **Build AwemeVision RELAXIN RootHide DEB**。
3. CI 首先静态检查源码文件、旧更新机制是否残留，再用 RootHide Theos 构建，检查真实 DEB 的包标识/架构/dylib/过滤器，然后上传 Artifact。
4. 下载安装前请先卸载 `com.huami.dyyy`，备份个人设置。

> 静态检查不等于实际编译，也不等于越狱进程成功注入。请以 GitHub Actions 完整通过与设备日志作为最终依据。
