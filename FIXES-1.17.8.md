# AutoAnswerCall 1.17.8 实验版（iOS 17.3）

## 本次归档(4).zip 的设备证据
- `02:24:34 +0000` 规则通过，SpringBoard 可读 2.19 MB 的 MP3。
- `AVAudioPlayer play` 返回成功；紧接着 `audio-finished-or-interrupted`，即播放没有维持。
- Settings 只读到 SpringBoard 新版宿主上报，没有同一时间的 InCallService 启动证明。因此老版本仅在 InCallService 显示的悬浮按钮可能从未运行。

## 改动
1. 将 InCallService 的“添加/Add Call”控件临时用一个可逆覆盖层替换成“停止播放”（同一列的位置），不发送原 Add 的事件。仅在有已连接来电且插件与音频均启用时显示；挂断/关闭插件时恢复原来的“添加”控件。若真实控件搜索失败，以该窗口下方左列位置显示测试覆盖层，运行日志会分别报告。
2. 除 bundle 过滤外，增加 InCallService 可执行文件名匹配尝试；是否在 RootHide/iOS 17.3 注入成功必须由 `MANUAL_HANDOFF 1.17.8 InCallService UI registered` 真机日志确认。
3. 修复 `[play]` 之后同步 `isPlaying` 假阴性导致的立即停止。新增 3 秒启动容错、实际播放进度和中断原因日志。
4. 仅当用户开启本地播放时，实验性切换 SpringBoard 音频会话为 `Playback + MixWithOthers`，完成后恢复旧类别。可能干扰系统通话音频，测试时务必有人在场，注意音量。

## 未完成、风险
- 这不是蜂窝通话上行音频注入；对方能否听见录音没有任何保证。
- 通话界面在 iOS 17.3 的 UIView 层级和被其他插件修改后的结构未经真机验证；控件隐藏/重建时可能无法覆盖或误定位。遇到问题应禁用插件恢复。
- Linux 无法编译 iOS tweak；需 GitHub Actions macOS + Theos 真正编译，检查日志。
- 测试后导出全部日志：`MANUAL_HANDOFF`、`AUDIO_TEST stage=configure-session`、`AUDIO_TEST playback-check`、`AUDIO_TEST result=interrupted`。
