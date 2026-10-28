# 影流助手 2.0.3：RootHide 严格链接与设置 Hook 恢复

适配基线：RELAXIN 0.4.8 / RootHide 白名单 / iOS 17.3 / 抖音 40.8.0。

## 根因拆分

1. 按用户设备验证反馈，`-Wl,-undefined,dynamic_lookup` 会让这个 RootHide 注入环境静默拒绝装载；现在删除此参数，改为 `-Wl,-undefined,error`，任何缺失符号会在 CI 链接时报错。
2. 2.0.2 默认 `AWEMEVISION_STARTUP=compat` 跳过 `DYYY.xm` 默认 Logos Hook 组（约 200+ 个 Hook），所以设置显示为开启，但功能根本没有注册。2.0.3 默认 `full`，`compat` 只保留给排障，不用于正常安装。
3. 主构造函数里部分 Hook 安装原来受用户协议、启动时功能开关控制；已将安装与开关解耦。按类别检测 Swift 类存在，缺失时记录信息而不是直接碰空类；这类缺失仍需真机核实。
4. 悬浮倍速按钮原来仅在启动时缓存开关状态；现在重新读取设置并在关闭时隐藏。
5. 长按菜单直接引用了抖音私有 Model 类的链接符号；改用 `NSClassFromString`，缺失类时无操作、不再制造未满足的链接符号。

## GitHub Actions

工作流默认 `full + legacy_loader_name=true + probe_only=false`，并使用 RootHide Theos。首先在 CI 执行源码审计与 Logos 预处理，再执行严格链接。

- **成功构建 DEB 仍不意味着真机所有功能均生效**，可见视频播放、长按、图集、自动连播等私有 Hook 需要设备测试。
- **CI 若报 `Undefined symbols for architecture arm64`**：不要恢复 `dynamic_lookup`，应根据报错逐个把抖音私有类引用改成运行时解析，或者显式链接真正的系统 Framework。
- 包验证阶段在 macOS 用 `nm -m -u` 检查是否含 `dynamically looked up` 符号。
- `PROBE_ONLY=1` 仅用于诊断，不能验证设置功能。`AWEMEVISION_STARTUP=compat` 只用于隔离默认 Hook，关闭后大量开关失效是预期结果。

## 设置测试分层

1. 全功能包加载：检查 `AwemeVision-early-load-2.0.3.log` 和 `AwemeVision-injection-2.0.3.txt`。
2. 更改开关：播放/画质、长按、自定义 UI、图集、倍速、自动下一条逐项验证。
3. 确认影响是否即时生效；需要新页面实例的 Hooks 可重新打开视频页面，不能误当成不生效。
4. 打开报错日志追踪 `AWEMEVISION-HOOK` 中是否有私有 Swift 类缺失。

**当前环境未安装 RootHide Theos/iOS SDK；仅提供静态检查及可在 GitHub Actions 进行的构建流程，不能宣称已通过真机验证。**
