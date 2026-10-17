# AutoAnswerCall 1.17.9：TelephonyUI 定向诊断与安全替换试验

依据用户提供的电话助手 2.3.2 安装包静态线索，**未复制第三方二进制或其私有源码**。

## 已修改
- 注入过滤改为仅 `Filter.Bundles`，与电话助手所观察的 InCallService Bundle 写法保持一致；不保证 RootHide 设备配置会允许注入。
- 采用 SYSTEM-COMPANION 被动观察模式：不再执行旧版接听 hook 发现与主动提交，降低与电话助手冲突的可能；探测、共享宿主报告、分片消息继续工作。
- 构造函数同步写 `CALLUI_BOOT`，用于辨认 InCallService 是否真正加载，而不是只靠 SpringBoard 或过期的进程心跳。
- InCallService 每 12 秒按需记录 `CALLUI inventory`：已装载的 `TPSlidingButton` / `TPPillView`、scene/window 数、控件类别样本。仅收集类与数量，不记录号码、联系人姓名及文本。
- 活动通话的「添加」先按无障碍标识/标题定位，再尝试只读的零参数视图 accessor；无真实控件就不再按屏幕百分比伪覆盖。
- 仅在确认已经连接的真实通话且定位到原生「添加」控件时临时替换：有音频显示「停止播放」，无音频显示「人工接管」，音频失败时按钮依然可见；停止或接管请求按 UUID 去重；通话结束恢复「添加」。
- 当 InCallService 的 `CXCallObserver` 未报告 UUID，允许在已找到「添加」控件和最近 12 秒 SpringBoard 正在播放状态双重验证后显示停止入口；停止请求仍绑定该 UUID。
- 春板播放器每 4 秒（仅播放进度已正常增长时）刷新状态，增加音频中断/路由变化/服务重置日志。

## 未解决／风险
- 真机尚未证明 InCallService 会加载 AutoAnswerCall；若无 `CALLUI_BOOT ... tag=incall`，按钮代码无法在通话界面运行。需检查 RootHide 注入开关、插件冲突、旧版本缓存。
- 当前 `AVAudioPlayer` 曾在蜂窝通话中停在 0 秒；本版仅增加诊断，没有通话上行音频注入，也不能保证手机本地实际发声。
- `TPSlidingButton` / `TPPillView` 来自来电控件相关静态字符串，**并不证明它们是已接通后「添加」控件**；没有直接 Hook 或擅自调用滑动接听方法。
- 建议备份安装包、有人工值守做测试，确认原「添加」、静音、挂断操作正常；出现通话异常应移除插件后恢复。

## 测试
测试脚本检查数据及代码结构，不等价于 iOS 17.3 真机编译/运行。
归档日志里优先查：`CALLUI_BOOT`、`CALLUI inventory`、`CALLUI add-accessor`、`native-add-identified`、`AUDIO_DIAG`、`AUDIO_TEST`。如果仍只有 SpringBoard 的 `CALLUI_BOOT`，说明宿主注入仍是主要障碍。
