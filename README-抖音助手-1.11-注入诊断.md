# 抖音助手 1.11：DEB 安装但不注入的诊断修正

这个版本主要针对“构建出 DEB，但没有注入抖音”的打包/诊断链路，不宣称已修复所有私有 Hook。

## 本次确定性修正

1. **默认构建 rootless**：过去 `make package` 默认 rootful，容易安装了错误构建方案。现可显式选择 `SCHEME=rootless`（默认）、`SCHEME=rootful`、`SCHEME=roothide`。
2. **GitHub Actions 独立构建**：切换 rootful / rootless / roothide 前运行 `make clean`，并独立保存每次生成的 DEB，避免缓存/文件混用。
3. **arm64 App 注入**：仅为第三方抖音 App 构建 arm64，避免与系统二进制专用的 arm64e ABI 混淆。
4. **注入筛选**：保留抖音两个已知 Bundle ID，增加可执行文件名 `Aweme` 的匹配项。
5. **加载探针**：动态库被加载时写 syslog，并在抖音容器的 `Library/Caches` 下创建 `DYYY-injection-1.11.txt`，以区分“未注入”与“注入了但功能未生效”。

## 选对 DEB 再安装

- Dopamine/大多数 iOS 15+ **Rootless** 越狱：`make clean && make package SCHEME=rootless FINALPACKAGE=1`。
- 传统 **Rootful** 越狱：`make clean && make package SCHEME=rootful FINALPACKAGE=1`。
- **roothide** 越狱：`make clean && make package SCHEME=roothide FINALPACKAGE=1`，必须使用兼容的 roothide Theos 环境。

**不要将三个版本同时安装**。先卸载旧版同包名插件，安装匹配设备越狱类型的 1.11 版。彻底关闭抖音并重新打开；必要时重启用户空间后再试。

## 注入诊断，按顺序检查

1. 确认越狱环境是否启用 tweak injection（例如 ElleKit/Substrate，以及针对抖音的注入开关）。若使用了 Choicy / iCleaner 等禁用注入的配置，先解除抖音的禁用项。
2. 检查实际安装内容：**Rootless** 动态库通常应在 `/var/jb/Library/MobileSubstrate/DynamicLibraries/DYYY.dylib`（roothide 使用自身的 jbroot 路径）；传统 **Rootful** 路径为 `/Library/MobileSubstrate/DynamicLibraries/DYYY.dylib`。同目录应有 `DYYY.plist`。
3. 在抖音彻底退出后重新打开，查系统日志中 `[DYYY-INJECT]`，或在抖音 App 的沙盒 `Library/Caches/DYYY-injection-1.11.txt` 查探针文件。如果探针存在，表示插件动态库已进入进程，问题转为 Hook/控件入口兼容性。若不存在，优先查安装路径/过滤器/注入框架/依赖/签名/进程崩溃。
4. 用 `tools/verify_deb.sh packages/你的.deb rootless` 对 **实际构建的 DEB** 检查包内文件和路径。不能仅靠源码看出真正安装的目录。
5. 若仍不注入，请提供：iOS 版本、越狱方案（Rootful/Rootless/roothide、Dopamine/其他）、抖音实际 Bundle ID、使用的 DEB、安装路径和启动日志。没有这些证据不能断言具体原因。

## 其他注意事项

- 当前环境没有 Theos/iOS SDK，**未实际编译 DEB、未测试设备注入**。
- 此次修正优先保证构建方案和诊断可验证，原有 1.10 的播放器/设置/UI Hook 未进行不必要的重写。
- 装包后如果抖音闪退，需查看 crash 日志，此时不一定是过滤器问题，而可能是某个 Hook 初始化导致的崩溃。

## 最小注入探针（诊断关键步骤）

完整插件可能因为某个抖音 40.8.0 私有 Hook 失配而崩溃；此时单看“没有设置入口”无法区分 **未注入** 和 **注入后崩溃**。

可以先生成只有一个日志构造函数、没有任何播放器/UI Hook 的诊断 DEB：

```sh
make clean
make package SCHEME=rootless PROBE_ONLY=1 FINALPACKAGE=1
```

请把 `SCHEME=rootless` 换成设备实际越狱方案。该包和正常插件**使用同一个包 ID**，只能单独安装测试；它不会显示任何插件设置，也不会修改抖音界面。

安装后彻底关闭抖音并重新打开；如果在抖音沙盒 Caches 下找到 `DYYY-injection-1.11.txt` 且包含 `mode: minimal-probe-only`，说明环境能加载诊断动态库。接下来卸载它，清理构建缓存，再装完整包：

```sh
make clean
make package SCHEME=rootless FINALPACKAGE=1
```

如果完整包却无法写入 `mode: full-plugin`，说明可能是在完整插件的构建、依赖、启动阶段出了问题，需要收集启动日志或崩溃报告。若最小包也完全没有日志，优先排查越狱注入框架、过滤器、进程、安装位置和包方案。
