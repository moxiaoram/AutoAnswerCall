# TrollRecorder 3.5.4-3287 接口分析（XPC 探测版）

## 已从用户提供的 TIPA 二进制中确认的字符串
- `TRAppIntentXpcClient` / `TRAppIntentXpcClientImpl` / `TRAppIntentXpcServer`
- `wiki.qaq.trapp.xpc`
- `PlayUplinkAudioIntent`
- `requestPlayContentsOfAudioFile:rate:volume:repeat:`
- `requestMuteExistingUplinks` / `requestUnmuteExistingUplinks`
- 独立可执行文件 `TRAudioPlayer` 中存在 `setMixToUplink:`、`play`、`pause`、`stop`。

## 本版改动
在 SpringBoard 找不到 `TRAudioPlayer` 时，尝试对观察到的 `wiki.qaq.trapp.xpc` 建立一个短时 `NSXPCConnection`，只记录连接中断/失效信息；不设置远程对象协议、不发送任何 RPC、不启动 TrollRecorder、不调用播放或静音方法。

## 重要限制
这只是服务可达性探测，不是上行播放修复。二进制字符串并不能单独证明该服务对 SpringBoard 开放、服务在后台已注册、该 XPC 接口允许外部调用，或播放方法的参数/返回值协议。只有确认服务端协议、方法签名、调用权限和停止/恢复行为后，才应实现真正的播放调用。
