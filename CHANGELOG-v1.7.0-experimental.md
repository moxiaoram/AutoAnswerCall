# AutoAnswerAudio 1.7.0-experimental

- 增加基于 TrollRecorder 3.5.4 二进制线索的实验性 AVAudioPlayer 私有方法调用：`initWithContentsOfURL:usesSharedAudioSession:error:` 与 `setMixToUplink:`。
- 自动接听后延迟 2.5 秒尝试播放设置中 `AudioFilePath` 指定的文件。
- 增加设置页实验开关 `PlayAudio`，以及设置页“停止通话上行播放”按钮；停止动作通过 Darwin 通知 `com.autoanswer.call.stopUplinkPlayback` 发送。
- **未编译、未在 iOS 17.3 真机验证；不能保证对端听到音频。** 如果系统不响应私有选择器，将记录日志而不退化为本机假播放。
- 尚未完成通话界面的悬浮停止按钮；目前停止按钮只在插件设置页中，后续还需接入悬浮控制面板。

## 全局日志增强（实验版修订）
- Tweak 与设置页统一写入 `/var/mobile/Library/AutoAnswerAudio/AutoAnswerAudio.log`。
- 每条日志附带时间、PID、进程名、源文件、行号和函数名，便于定位具体失败位置。
- 使用追加写入和文件锁，降低 SpringBoard 与设置页同时写日志时的交错风险；同时镜像输出到系统日志。
- 设置页新增“查看 / 复制全局日志”按钮，可直接查看并复制日志；也可手动清空后重新复现问题。
- 设置页的导入、选择、删除、试听、停止请求等关键动作会写入同一日志。
- 日志仍不能证明私有上行混音接口可用；需要设备实际日志和通话测试确认。
