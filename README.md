# ClashAssist 0.4.0 · 详细日志与真实接口调度

已删除“开始模拟”入口、`CALabCore.h` 和合成收益/模拟战斗代码。现在的“开始自动战斗”调用 `CABattleRuntime`：读取后端真实状态 → 搜索并筛选对手 → 逐个部署 → 等待自然结束或到时请求结束 → 确认结算后停止。

**这份源码尚不能直接自动打真实对局。** 原包只有三个候选观测入口，没有准确的函数签名、对象生命周期、兵种/落点参数或资源/结算读取接口。本次没有编造这些信息，也没有提供一个返回假成功的实现。没有注册真实后端时，启动明确报“未接入真实游戏后端”，不会执行动作。一次只处理一场，不自动循环、不自动回村。

## 日志变化

- 安装诊断包含三个候选入口的预期/实际指纹及签名尚未验证的标志。
- Hook 时间线容量 8192 条，保留入口/返回配对、线程、嵌套深度、调用点偏移、原始参数机器字及耗时。
- 修复并发写入环形槽位的混合记录问题：记录提交、快照、会话重置使用同一互斥锁。
- 每次入口保存会话代号，旧会话函数返回不会写入新会话；同会话停止后的晚返回仍可保留在内存。停止时的文件快照未必包含之后才返回的事件。
- 观测时间从 60 秒延长至 300 秒；人工标记保留。
- 观测期间每 5 秒及停止时，异步原子更新 `Caches/ClashAssist/observation-latest.json`。仅保留最近一份观测快照，最近 5 秒可能尚未写盘。
- 新增结构化事件日志：运行 UUID、动作 UUID、请求/接受结果、状态版本、场景、资源、已确认下兵数、阶段变化、错误域/错误码和停止原因。它记录动作被接受与状态确认的区别。
- 事件同时保留在内存（最近 4096 条）和应用 `Caches/ClashAssist/events.jsonl`，4 MiB 滚动，另留一份 `.1`。写盘失败显示在报告 `journal.diskError`。缓存可能被系统清理，异步写入也不保证异常退出前最后一条已落盘。
- 面板支持复制完整 JSON 和系统分享面板导出 JSON 文件。完整报告包含 `observation`、`runtime`、`journal` 三部分。Hook 明细在观测快照中，JSONL 保存运行事件，不是所有 Hook 明细。
- 分析脚本兼容旧版平铺报告及新版完整报告，新增配对缺失统计及 p50/p95/最大耗时。缺失配对可能源于覆盖或仍未返回，不能直接判断为崩溃。

Hook 记录路径仍有开销，快照时其他记录线程可能短暂等待。`durationMs` 是包装器测得的时间，包含部分记录开销；不是纯原函数耗时。现有 Hook 的 `void(void *, ...)` 签名仍来自原包，指纹一致并不证明 ABI 正确，本次没有验证这些签名。候选 Hook 安装失败后本进程不重试，避免部分安装后再次 Hook；重新调查需完全重启游戏。

## 使用日志

1. 在目标游戏前台打开面板，点击“观测调用 300 秒”。
2. 在手动搜索、部署、结束、结算前后点击对应标记，并实际完成操作。
3. 点击“导出完整诊断 JSON 文件”保存文件，或复制完整 JSON。
4. 在电脑分析：

```sh
python3 tools/analyze_report.py diagnostic-report.json
```

报告中的机器字可能包含进程指针，不解引用；调用次数和偏移不证明动作成功。当前观测 Hook 只支持原包的镜像 UUID `0A02113F-E020-32D6-A674-E1E8622BBA2D` 和原指纹，不会自动适配其他游戏构建。

## 接入真实后端

实现 `CABattleRuntime.h` 中的 `CAVerifiedGameBackend`，将实现文件加入 `Makefile` 的 `ClashAssist_FILES`，在主线程注册后再启动：

```objc
NSError *error = nil;
// backend 是你们已实现并验证的 id<CAVerifiedGameBackend> 对象。
BOOL registered = [CABattleRuntime.shared registerBackend:backend error:&error];
```

以上仅为注册方式，仓库未提供具体 `backend` 对象。接入必须具备：

| 接口/数据 | 契约 |
| --- | --- |
| expectedBundleID / expectedBuildVersion | 与当前 Bundle ID 和 CFBundleVersion 精确一致；非空 |
| validate: | 核对准确镜像 UUID、ABI、对象有效性、调用线程、完整下兵计划和操作前置条件 |
| readWorld:error: | 返回真实观察的 CAWorld；读取失败返回 NO，并给出 NSError |
| revision | 非零，运行中不倒退；只为新的真实观察分配版本，不能用本地计时器伪造。游戏状态不变也可以有新的真实观察版本 |
| opponentID | 当前对手场景的非零临时标识；每次完成新搜索必须变化；从选中对手至结算保持不变。使用本地场景标识，不要放玩家账号 ID |
| gold / elixir / dark | 当前候选对手的真实资源；任一低于配置则搜索下一个 |
| remainingUnits / deployedUnits | 真实可部署总单位数和本场累计确认部署数。部署接口每次只发一个单位，必须观察到精确加一才能继续；禁止混入手动部署 |
| searchOpponent: | 在家园发起搜索，或在候选对手页面搜索下一个；完成由新的 opponentID 确认 |
| deployOneUnit: | 按后端已验证的兵种选择、场景坐标和有效落点计划提交一个单位 |
| endBattle: | 处理真实结束及确认流程；结算由 readWorld 确认 |
| cancelPendingActions | 停止、错误或结算时撤销后端尚未提交的异步动作，必须可重复调用；已接受的游戏指令无法撤销 |

所有后端方法在主线程执行，必须迅速返回，不能阻塞游戏线程。返回 YES 只表示请求被接受；实际成功由之后的读取确认。`endBattle:` 如需异步二次确认，由后端管理；停止/错误/结算时运行时调用 `cancelPendingActions`，后端必须撤销未提交的后续操作。

当前流程使用 20 秒动作确认超时；搜索上限与单场部署上限可配置；战斗秒数从候选对手通过筛选时开始计时（包括部署阶段）。达到时间后，必须有新的真实“战斗中”观察才请求结束。状态未知、版本倒退、对手中途变化、读取失败、提交失败、确认超时，都会停止后续指令；不会盲重试。长按悬浮按钮或切后台也停止后续指令。停止调度不等于撤销游戏已接受的指令，不自动结束当前对局。

为完成具体游戏后端，还需要准确游戏版本号/CFBundleVersion、同版本可分析的可执行文件或已验证的函数声明/调用代码，以及带人工标记的完整真机日志；仅有本 ZIP 的三个偏移无法补齐。

## 测试与构建

```sh
cc -std=c11 -Wall -Wextra -Werror -I. tests/battle_core.c -o /tmp/clash-battle-test
/tmp/clash-battle-test
python3 tests/verify_diagnostics.py
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tools/analyze_report.py tests/fixtures/sample-diagnostic-report.json
```

C 测试用固定输入验证调度器，包括未确认不重复下兵、旧对手过滤、缺失观察超时、结算确认、搜索上限、状态倒退等。这些输入只用于测试，不编入插件，不是实际游戏测试。

```sh
make clean
make package FINALPACKAGE=1 ARCHS=arm64e THEOS_PACKAGE_SCHEME=roothide
```

目标仍为 iOS 15+ / arm64e / RootHide，Bundle 过滤为 `com.supercell.magic.china`。当前交付环境无 iOS SDK/Theos，未编译 `.deb`，未验证注入、真机 UI、原 Hook ABI 或真实战斗。GitHub Actions 已更新新源文件和测试，尚未执行远端构建。
