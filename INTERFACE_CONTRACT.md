# 真实游戏后端接口契约（0.4.2）

本文件定义调度器要求的后端行为。它不是游戏内部 API 的发现结果，也不代表本仓库已有具体游戏后端。当前仓库仍然没有可验证的真实游戏操作实现。

## 1. 读取接口 `readWorld:error:`

每次成功调用必须返回一个**同一时刻、同一场景的完整快照**。不能从不同帧拼接资源、场景和兵力值；不能使用模拟值；不能把“未知”填成 0。

| 字段 | 含义 | 有效条件 | 校验要求 |
|---|---|---|---|
| `scene` | `home/searching/opponent/fighting/settlement/unknown` | `CAWorldHasScene` | 只能来自已验证的场景状态源；不允许只凭某个 Hook 命中推断 |
| `revision` | 成功采样序号 | `CAWorldHasRevision` | 每次新的成功采样严格递增，即使场景未变化；不可用定时器伪造 |
| `observedAtMonotonic` | 快照采样时刻 | `CAWorldHasTimestamp` | 与 `NSProcessInfo.processInfo.systemUptime` 同时钟；运行时拒绝未来或超过 1.5 秒的快照 |
| `opponentID` | 本次对手的临时本地身份 | `CAWorldHasOpponentID` | 新搜索确认成功后必须改变；不能使用玩家账号 ID；同场战斗期间稳定 |
| `gold/elixir/dark` | 当前候选对手剩余可掠夺资源 | `CAWorldHasOpponentResources` | 用于门槛筛选；不用于判断本场累计收益增长 |
| `lootGold/lootElixir/lootDark` | 本场累计已获得战利品 | `CAWorldHasBattleLoot` | 用于五秒无增长检测；战斗内应单调不减；任何倒退都停止调度并记录错误 |
| `remainingUnits` | 当前仍可部署的单位数 | `CAWorldHasTroops` | 一次单兵部署被确认时必须恰好减少 1 |
| `deployedUnits` | 本场累计已确认部署单位数 | `CAWorldHasTroops` | 每个单兵请求必须在新快照中恰好增加 1；跳增、倒退或无确认均不得继续发兵 |
| `validFields` | 哪些字段实际可信 | 总是返回 | 字段缺失与合法的数值 0 必须区分 |
| `evidenceFlags` | 后端自定义的证据来源位 | 可选 | 只描述数据来源，不是置信度，也不能代替验证 |

### 按场景要求的有效字段

- 家园 `CAHome`：场景、revision、采样时间。
- 搜索中 `CASearching`：场景、revision、采样时间。
- 对手 `CAOpponent`：基础字段 + 对手身份 + 对手资源 + 兵力计数。
- 战斗中 `CAFighting`：基础字段 + 对手身份 + 累计战利品 + 兵力计数。
- 结算 `CASettlement`：基础字段 + 对手身份 + 最终累计战利品。

字段缺失、采样过期、revision 倒退、对手身份变化、累计战利品倒退都必须 fail-closed：取消尚未提交的后端动作并停止，不允许猜值或盲目重试。

## 2. 动作接口及确认语义

所有方法必须在主线程迅速返回，不得阻塞游戏线程。`YES` 只表示请求已接受，不表示游戏动作已经完成；实际结果必须由后续 `readWorld:error:` 的新 revision 确认。

| 方法 | 前置条件 | 请求后的确认条件 | 超时/失败行为 |
|---|---|---|---|
| `searchOpponent:` | 已确认家园，搜索次数未超限 | 进入搜索中，随后出现不同的非零 `opponentID` 和完整对手资源快照 | 超时则停止；不重放未知命令 |
| `deployOneUnit:` | 对手资源过门槛、兵力可用、当前对手身份稳定 | `deployedUnits` 恰好 +1 且 `remainingUnits` 恰好 -1 | 任何跳增、倒退或超时均停止 |
| `endBattle:` | 新鲜快照明确为 `CAFighting`，且累计战利品连续 5 秒无增长，或达到单场超时 | 真实 `CASettlement` 场景和最终战利品快照 | 不能把“请求已接受”当作结束成功 |
| `returnHome:` | 已观察到 `CASettlement` | 后续新 revision 明确观察到 `CAHome` | 超时则停止，不得直接开始下一轮搜索 |
| `cancelPendingActions` | 停止、读取错误、超时、结算或异常 | 后端不再提交尚未发出的延迟动作 | 必须幂等；已被游戏接受的指令无法撤销 |

## 3. 状态机和时间策略

- 采样间隔：运行时每 250 ms 请求一次真实快照。
- 快照最大年龄：1.5 秒；超出即停止。
- 动作确认超时：20 秒。
- 单场硬超时：配置的 `battleTimeout`（1–1800 秒）。
- 无战利品增长结束阈值：固定 5 秒，配置值不等于 5.0 会被拒绝；金币、圣水或黑水任一累计值增加都会重置计时。数值下降不重置计时，而是视为数据异常并停止。
- 搜索上限：`maxSearch` 统计搜索请求次数，包含被资源门槛跳过的候选。
- 部署上限：`maxUnits` 统计已确认的单兵部署数，不是请求数。
- 结束流程：结束请求 → 真实结算确认 → `returnHome:` 请求 → 真实家园确认 → 未达到搜索上限时才发起下一轮搜索。
- 应用切后台、状态读取失败、未知场景、revision 倒退、对手身份改变、部署未精确确认或结算超时，均停止自动指令。

## 4. 精确构建与接口验证

后端 `validate:` 必须核对准确 Bundle ID、`CFBundleVersion`、Mach-O UUID、调用约定/参数类型、对象生命周期、允许调用线程和动作前置条件。当前日志中的偏移 `0x5ddae0`、`0x5dfd84`、`0xf949f8` 是观测候选；三个 `signatureVerified` 都为 false。调用点偏移 `0x69ab9c` 等不是函数地址。

在未提供已验证的真实后端前，插件必须显示“未接入真实游戏后端”并拒绝自动战斗；不提供伪造资源读取、不返回假成功、不将原始参数机器字解引用或重放。
