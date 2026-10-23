# ClashAssist 0.4.6 · 后端就绪诊断

## 本版用途

0.4.6 增加了运行时 `backendReadiness` 诊断和“检查自动战斗后端就绪条件”按钮，并从设备 UI/目标 tweak 构建中移除了离线模拟入口。真机验证仍是只读观测；本版不是完整自动战斗成品，不会调用未知函数或发送游戏操作。

### 使用步骤

1. 在已安装插件的测试设备上打开游戏，并让游戏保持前台。
2. 打开 ClashAssist 面板，点击 **“启动真机接口验证（只读 300 秒）”**。
3. 按正常游戏操作执行一次搜索、一次单兵部署、一次手动结束、结算后返回/进入下一轮。每个动作前后使用对应的人工标记。
4. 对照实际屏幕填写“当前真实画面快照”：
   - `scene`: `home` / `search` / `battle` / `settlement` / `other`
   - 对手可掠夺金币、圣水、黑水
   - 本场累计金币、圣水、黑水
   - 剩余兵力、已部署兵力
5. 不确定的字段留空。空值会导出为 JSON `null`，不会当作 0。
6. 导出完整诊断 JSON，并检查 `interfaceAnalysis.manualStateAnalysis` 中的相邻快照差值。

## 报告内容

- Hook `enter` / `return`、相对单调时钟、调用耗时、线程 ID、嵌套深度和 caller offset。
- 搜索、部署、结束结算、下一轮的人工标记时间窗口及候选调用分组。
- `validationSessionID` 用于隔离不同验证会话的手动状态快照。
- `manualStateAnalysis` 包含操作者输入的屏幕状态和相邻快照差值。

## 真机验证操作手册

详细步骤见 [`REAL_DEVICE_VALIDATION_GUIDE.md`](REAL_DEVICE_VALIDATION_GUIDE.md)。

## 真实后端契约参考

`INTERFACE_CONTRACT.md` 描述自动调度器将来需要的状态与动作契约；它是设计约束，不是已发现的游戏内部 API。`LOG_ANALYSIS_2026-10-23.md` 记录现有日志能支持的结论。

## 严格限制

- 所有候选函数的 `signatureVerified` 仍为 `false`，`invocationAllowed` 始终为 `false`。
- `callerOffset` 是调用来源偏移，不是被 Hook 函数的可调用地址。
- 指纹匹配和调用正常返回不证明函数语义、ABI 或参数类型。
- 手动录入的画面数值不是游戏 API 直接读取，不能用于自动化决策。
- 本模式不读取游戏内存、不截图、不抓取网络、不调用候选函数、不自动搜索/部署/结束。设备 UI 不再显示离线模拟自动流程按钮；离线测试仅保留在开发测试文件中。
- `runtime.backendReadiness` 会明确列出缺失的后端注册、bundle/build 匹配、验证状态、方法和新鲜完整状态快照等阻塞项。
- 应用进入后台时，现有安全逻辑会停止观测；请保持游戏和插件处于前台。

## 构建

目标配置：iOS 15+、arm64e、RootHide/Theos。请在已配置 Theos 的设备/构建环境执行：

```sh
make clean
make package FINALPACKAGE=1 ARCHS=arm64e THEOS_PACKAGE_SCHEME=roothide
```

本交付环境没有执行 iOS/Theos 编译、`.deb` 打包或真机安装。不要把源码 ZIP 当作已验证的安装包。

## 测试

```sh
cc -std=c11 -Wall -Wextra -Werror -I. tests/battle_core.c -o /tmp/clash-battle-test
/tmp/clash-battle-test
cc -std=c11 -Wall -Wextra -Werror -I. tests/replay_automatic_loop.c -o /tmp/clash-replay-test
/tmp/clash-replay-test
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tests/verify_diagnostics.py
```

C/fixture tests validate local logic and report structure only; they do not establish real game API behavior.
