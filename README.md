# ClashAssist 0.4.2 · 证据基线注入与安全调度诊断

本版把用户提供的 2026-10-23 观测报告中**有证据支持的摘要**加入源码，并在运行时预检事件中输出。它不会把候选 Hook 的调用次数推断为搜索、下兵或结束动作，也不会回放未定型的原始参数。

## 本版新增

- `evidence/observed-baseline-2026-10-23.json`：已脱敏的报告摘要，可分享和复核。
- `CAObservedEvidence.h`：把观测基线以只读诊断字段注入运行时。
- `runtime.preflight`：记录当前 bundle/build、应用前后台状态、后端是否注册和观测基线。
- `runtime.start.blocked`：后端未接入时明确列出缺失能力，不会假装开始自动战斗。
- `backend.registered` / `backend.build-mismatch`：增加后端期望版本与实际版本诊断。
- `action.request`：增加请求时的状态阶段和触发原因，便于关联状态机决策。
- 新增证据基线单元测试。

## 现有日志真正支持的结论

- 观测时长约 186.9 秒，135 条时间线记录，没有丢记录。
- 统一命令候选命中 67 次；普通按钮分发和结束确认候选均为 0 次。
- 三个候选签名都未验证；没有人工操作标记、真实场景/资源/战利品采样。
- 运行时后端 `not-connected`，搜索次数和确认部署次数均为 0。

## 当前可用范围

可以运行并测试纯 C 状态机、离线报告分析器和诊断事件；可以验证资源门槛、累计战利品五秒无增长、超时、结算/返回家园状态转换的**合成数据行为**。

尚不能在真实游戏中自动搜索、部署、结束或返回家园，因为日志不包含已验证的操作接口、真实资源读数或场景数据。官方规则禁止未经授权的机器人和游戏自动化；本项目不会通过猜测私有偏移或重放原始参数来绕过这一限制。

## 本地测试

在配置了 C 编译器和 Python 3 的环境中：

```sh
cc -std=c11 -Wall -Wextra -Werror -I. tests/battle_core.c -o /tmp/clash-battle-test
/tmp/clash-battle-test
python3 tests/verify_diagnostics.py
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tools/analyze_report.py /path/to/ClashAssist-diagnostic.json
```

目标构建环境：iOS 15+、arm64e、Theos/RootHide。此环境未提供 iOS SDK/Theos，未构建 `.deb`，未进行真机或真实游戏验证。
