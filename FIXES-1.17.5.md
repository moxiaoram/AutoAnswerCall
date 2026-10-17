# AutoAnswerCall 1.17.5 — 系统接听 + 本地音频 + 人工停止按钮

## 实际功能
- **系统自动接听**由 iOS 17.3「辅助功能 → 触控 → 通话音频路由 → 自动接听通话」负责；插件不在兼容模式下发出任何接听请求。
- 在插件设置中启用「启用插件策略」「接通后播放本地音频」及「系统接听后本地音频＋停止按钮」，选中有效的音频。最后一个开关默认关闭。
- 插件观察来电且符合规则，观察到 `CXCallObserver.hasConnected=yes` 后，由 SpringBoard 尝试用 `AVAudioPlayer` 播放**本机**音频。
- 如果播放开始，SpringBoard 将通话 UUID + `playing` 原子写入 `playback-state.plist`，并发送 Darwin 唤醒。InCallService 接入自己的可见 `UIWindow` 后，在右上角显示「停止播放」。点击后按 UUID 写入 `playback-stop-request.plist` 并发送通知。SpringBoard 读取匹配请求后停止本机播放、发布 `stopped` 确认，按钮消失。
- 点击不会挂断通话，也不会改变麦克风/静音状态；你可以立即手动说话。通话结束、插件停止、音频自然结束均移除按钮。
- 1.17.5 增加 `MANUAL_HANDOFF` 诊断，包括窗口未找到、按钮创建、停止请求、播放宿主确认。

## 使用及边界
1. iOS 自动接听先设置 6 秒，插件兼容模式下不另发延迟接听动作；插件的 Delay 不控制 iOS 系统延迟。
2. 手动接听也可能触发 `hasConnected`，所以如果在此模式且符合策略，本地音频仍可能启动。
3. 共享路径为 `/var/mobile/Library/Application Support/AutoAnswerCall/`；如果进程没有读写权限，日志会写 `statePublished=0` 或 `stopRequestWritten=0`，界面按钮可能不可用。
4. **未实现蜂窝通话音频上行注入**。`AVAudioPlayer` 不是电话麦克风信号来源；即使播放器工作，也不代表来电人能听到。真正向来电方送录音需要另行研究并在真机验证音频路由。
5. **尚未 iOS 17.3 / RootHide 真机或 Theos 编译验证**。InCallService 的 UIWindow 是否允许显示该控件需测试；按钮仅在本机播放状态且该进程观察到当前来电已连接时显示。
6. 系统自动接听依然全局生效，不受插件的来电白名单影响；该名单仅约束本地播放。

## 验证日志
搜索 `SYSTEM_ANSWER_TEST`、`AUDIO_TEST`、`MANUAL_HANDOFF`、`CONFIG_DIAG`；请在真实通话过程中点击停止后导出全量日志。
