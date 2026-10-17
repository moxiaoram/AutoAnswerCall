# AutoAnswerCall 1.17.9：iOS 17.3 通话界面「添加」替换与本机播放诊断版

1. iOS 系统自动接听负责真正接通电话，插件只观察连接并尝试播放本机预设 MP3；不开启独立 CallKit 蜂窝接听。
2. InCallService（需要实际成功注入）在通话接通后临时用「停止播放」覆盖通话界面的「添加」按钮位置，停止后仍保持通话连接；通话结束或关闭插件时恢复原按钮。没有检测到真实「添加」控件时使用仅供测试的下左方位置估算，日志明确标注。
3. 本机 SpringBoard 音频播放器启用启动缓冲期、实际播放进度检查，并实验性使用 `AVAudioSessionCategoryPlayback + MixWithOthers`。此举有干扰电话音频的风险，测试期间建议有人值守。
4. 关键日志：`AUDIO_TEST playback-check`、`AUDIO_TEST stage=configure-session`、`MANUAL_HANDOFF native-add-replacement`、`Loaded 1.17.9`。
5. **不实现蜂窝语音上行音频**，来电人未必能听到音频；尚未在 iOS 17.3 真机上验证编译、按钮位置、进程注入或本机播放。

变更详见 `FIXES-1.17.9.md`，老版本说明仍保留作为历史记录。

## 历史版本文档
保留 1.17.2、1.16.0、1.15.0 的诊断历史；请参考 FIXES 文件，历史日志不是新版实现承诺。
