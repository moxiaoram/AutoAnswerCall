# 影流助手 2.0.3（RELAXIN / RootHide · 严格链接与功能恢复）

这是基于 DYYY 开源项目的独立二次开发版本，保留上游 `LICENSE` 和署名；**不是原项目的官方升级包**。

**请先阅读：** [2.0.3 严格链接与设置恢复说明](README-2.0.3-严格链接与设置恢复.md)，以及 [RootHide GitHub Actions 构建规范](README-RELAXIN-RootHide-GitHubActions-构建规范.md)。

## 设备与安装包标识

- 目标：iPhone15,3 / iOS 17.3 / RELAXIN 0.4.8 / RootHide 白名单 / 抖音 40.8.0。
- 抖音 Bundle ID：`com.ss.iphone.ugc.Aweme`。
- 独立 DEB 标识：`com.local.awemevision.relaxin`，架构 `iphoneos-arm64e`。
- 默认加载文件名：`DYYY.dylib` + `DYYY.plist`（兼容旧版的加载命名；**不会变更独立 DEB 身份**）。
- 原 DYYY 的**联网更新检测和远程配置更新已经移除**，仅保留本地配置能力。

## GitHub Actions 打包

工作流：`.github/workflows/build.yml`。

默认参数：
- `startup_mode = full`：安装主要 Hook 组，使视频播放、界面、长按、图集和其他设置的代码能够执行。
- `legacy_loader_name = true`：沿用已知运行环境的动态库文件名称。
- `probe_only = false`：正常的完整插件。`true` 仅用于注入探针，不包含功能。

编译采用严格链接参数 `-Wl,-undefined,error`，**严禁使用 `-Wl,-undefined,dynamic_lookup`**。CI 编译完成后，校验 DEB 架构、载入路径和 Mach-O 动态导入符号。

如因未定义符号导致构建失败，需要根据 linker 日志修复相应私有类的链接方式或正确链接系统 Framework，绝不能通过恢复 `dynamic_lookup` 绕过。

本地（仅做静态检查）:

```bash
python3 scripts/check_relaxin_source.py
python3 scripts/audit_settings_bindings.py
```

**当前源码包未通过真实 iOS SDK 编译或真机注入验证。** 270 多项设置有代码引用，不代表每项在抖音 40.8.0 上均已验证。详细清单在 `SETTING_BINDINGS_AUDIT.json`。

### 许可与致谢

保留原项目 `LICENSE`，以及历史 README 资料中的上游作者和维护记录。
