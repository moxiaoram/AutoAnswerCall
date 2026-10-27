# TrollRecorder 3.5.4-3287 接口分析（v1.7.4 源码附录）

## 已确认的静态线索
- App Intent 元数据定义 `PlayUplinkAudioIntent`，包含 `audioFile`、`volume`、`shouldRepeat`。
- 二进制字符串包含 `TRAppIntentXpcClient`、`TRAppIntentXpcClientImpl`、`TRAppIntentXpcServer`。
- `TRCallMonitor` 相关二进制包含 `requestPlayContentsOfAudioFile:rate:volume:repeat:`、`playCustomAudioWithContentsOfFile:rate:volume:repeat:`、`playBackgroundAudioWithContentsOfFile:rate:volume:repeat:`。
- 另有 `setUplinkMuted:`、`requestMuteExistingUplinks`、`requestUnmuteExistingUplinks`。
- 独立 `TRAudioPlayer` 可执行文件包含 `setMixToUplink:`、`play`、`pause`、`stop`。
- `TRAudioPlayer` 不是可以假定已加载在 SpringBoard 内的系统类；它属于 TrollRecorder 的独立 helper。

## 本版源码对应的改动
- 播放尝试现在先检查音频文件，再记录已确认的候选请求方法名。
- 不在 SpringBoard 中创建 `TRAudioPlayer` 实例。
- 仅保留 `wiki.qaq.trapp.xpc` 的诊断性连接测试，不设置远程协议、不发送 RPC。

## 尚未确认（不能臆造）
- `%@/machXPC_host_q` 中的实际 host 值及服务注册过程。
- XPC/MachXPC 连接的初始化参数、远程接口协议与方法编码。
- 播放请求的参数 ABI、返回值、错误处理以及播放器启动参数。
- `setMixToUplink:` 的调用时机和音频会话配置。
- 停止播放后解除静音、恢复真实麦克风的完整顺序。
- iOS 17.3 Relaxin RootHide 真机的通话上行成功验证。

**因此，v1.7.4 是保守的源码证据更新，不宣称已经实现通话对端可听的音频注入。**
