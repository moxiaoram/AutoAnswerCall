# AutoAnswerAudio v1.8.0 实验桥

## 本轮改动
- 不再从 SpringBoard 直接实例化不存在于本进程的 `TRAudioPlayer`。
- 新增 SpringBoard -> Darwin notification + 命令 plist -> `TRCallMonitor` 的跨进程桥。
- 在 `TRCallMonitor` 进程中动态查找 `TRRecordingManager sharedManager`、取得 `session`，调用静态反汇编确认的 `playCustomAudioWithContentsOfFile:rate:volume:repeat:`。
- 停止请求尝试调用 `terminateBackgroundAudioIfNeeded`。
- 命令文件设有 30 秒有效期，避免 helper 启动后播放过期请求。

## 静态依据
- `TRRecordingSession -playCustomAudioWithContentsOfFile:rate:volume:repeat:` IMP `0x100034bb0`。
- `TRRecordingSession -playBackgroundAudioWithContentsOfFile:rate:volume:repeat:` IMP `0x100035b10`。
- `TRRecordingSession -terminateBackgroundAudioIfNeeded` IMP `0x100037b1c`。
- `TRAppIntentXpcServiceConnection -requestPlayContentsOfAudioFile:rate:volume:repeat:` IMP `0x100119a14`，其调用链取得 `TRRecordingManager` 并进入活动 session 的播放入口。

## 当前限制
- 这是基于静态反汇编的新实验性实现，尚未在 Theos 环境编译。
- 尚未验证 RootHide/ElleKit 是否能按 `Executables=TRCallMonitor` 成功注入该 helper。
- 尚未验证 helper 进程启动时机、活动 session 是否存在、跨进程命令文件权限，以及对端实际是否听到音频。
- `terminateBackgroundAudioIfNeeded` 是否完全停止自定义播放仍需真机验证。
- 不能把本源码包视为已验证可用的 deb。


## v1.8.1 后续诊断
由于设备日志未出现 TRCallMonitor 记录，v1.8.1 将 SpringBoard 与 TRCallMonitor 分成两个 dylib 和独立 filter，先验证注入目标。
