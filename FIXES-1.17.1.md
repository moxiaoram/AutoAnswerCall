# AutoAnswerCall 1.17.1 静态修复版

源文件来自用户上传的 1.17.0 完整源码包，保留 RootHide、arm64e、Theos 工程结构。

## 本次修复

1. **跨通话误抑制**：把接听按钮跨进程 `buttontap` 消息改为 `buttontap.<宿主>.<通话UUID>`，只为当前真实通话注册观察者，结束时注销。避免旧通知让下一通来电错误让出。
2. **点击失败锁死**：若扫描后点击机制无法成功调用，回滚该 UUID 的点击占位，不再错误地永久标记“已点击”。
3. **事件发送异常**：发送 TouchUpInside 抛异常不再误报为成功；TouchDown 仅在确有对应 target/action 且未发生 TouchUp 时发送，防止重复分发。
4. **结算窗口设置复核**：1.2 秒等待后点击前再次检查启用设置、模式、通话状态和排除策略。
5. **记录区分失败阶段**：未连接时区分未触发、无有效动作、已提交请求、已经发送按钮事件，不再全部显示相同结果。
6. **简化设置页**：移除 Root.plist 的所有灰色 footerText 和 subtitle，以及内部诊断页面的分组底部解释文字；保留有用的行内状态、日志数据和输入占位提示。
7. **版本更新**：1.17.0 → 1.17.1，方便覆盖安装。
8. **CI**：保留原有 GitHub Actions 流程，版本检查改为 1.17.1，使用 macos-15。

## 重要限制

- 截图中的 SpringBoard/InCallService 探针到达只能证明相关通知到达；不能确认扫描到了有效接听 UI 或连接成功。
- 仍依赖 iOS 私有电话 UI，且 CallKit 公共 `CXAnswerCallAction` 曾返回 unentitled。**此包不保证解决自动接听本身**；只有在真机日志证明找到了可用按钮/动作后才能进一步定位。
- 尚未在 iOS 17.3 RootHide 真机运行，也没有 iPhone SDK/Theos 编译条件；必须先在 GitHub Actions 实际编译、安装后验证。
- 如果只是想让所有电话自动接通，iOS 自带“设置 → 辅助功能 → 触控 → 通话音频路由 → 自动接听通话”通常比未验证私有按钮模拟更可靠；它不支持插件的排除名单逻辑。

## 下一次实机取证

从设置里的“分享全部运行日志”导出文件，并特别检查：来电对应 UUID 的 `Eligibility`、`BUTTON_SCAN`、`BUTTON_CANDIDATE`、`BUTTON_TAP`、`LOG-ONLY`、`unentitled` 和 `hasConnected`。可以隐藏来电号码再分享。
