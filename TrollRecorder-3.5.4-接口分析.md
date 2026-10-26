# TrollRecorder 3.5.4 TIPA 静态分析（2026-10-26）

## 文件身份
- Bundle ID: `wiki.qaq.trapp`
- Short version: `3.5.4`
- Build: `3287`
- MinimumOSVersion: `15.0`
- 主程序：`TRApp`；辅助可执行文件：`TRAudioPlayer`。

## 观察到的二进制证据
- `TRAudioPlayer` 的字符串/Objective-C selector 中包含 `setMixToUplink:`。
- 同一可执行文件包含 `initWithContentsOfURL:usesSharedAudioSession:error:`、`play`、`pause`、`stop`、`setVolume:` 等选择器。
- `TRApp` 中包含 `requestPlayContentsOfAudioFile:rate:volume:repeat:`、`requestMuteExistingUplinks`、`requestUnmuteExistingUplinks`，并有 `TRAppIntentXpcServer/Client` 字符串。
- `TRApp` 中包含 `PlayUplinkAudioIntent` 与显示文案 `Play Uplink Audio`。

## 证据边界
以上为二进制字符串和元数据线索，不能单凭字符串确认完整调用链、权限要求、跨进程通信协议或 iOS 17.3 兼容性。`requestPlayContentsOfAudioFile:rate:volume:repeat:` 是应用内部方法名，不应当作可直接从 SpringBoard 调用的公开接口。

## 实验接入方案
当前实验源码在 SpringBoard 内尝试动态调用 AVAudioPlayer 的 `initWithContentsOfURL:usesSharedAudioSession:error:` 和 `setMixToUplink:`。这是为了验证选择器在 iOS 17.3 SpringBoard 进程中是否可用；尚未验证它是否真的将音频送入蜂窝电话上行链路。

停止通知：`com.autoanswer.call.stopUplinkPlayback`（Darwin notification）。该通知只用于实验性停止路径，尚未接入用户可见悬浮按钮。


## v1.7.1 源码修正结论
- 上一版把 `initWithContentsOfURL:usesSharedAudioSession:error:` 错误地发给系统 `AVAudioPlayer`，用户日志已证明该 selector 不存在。
- 该 selector 和 `setMixToUplink:` 的二进制线索来自 TrollRecorder 的 `TRAudioPlayer` 可执行文件；不能据此认为 SpringBoard 进程已经加载该类。
- v1.7.1 改为先通过 `objc_getClass("TRAudioPlayer")` 检查类是否在当前进程运行时可见；只有类和所需 selector 均存在才尝试创建实例。
- 若类不存在，日志会指出下一步应分析 TrollRecorder 的 XPC/IPC 协议。尚未从二进制恢复该协议，因此本版本不声称完成直接接入。
