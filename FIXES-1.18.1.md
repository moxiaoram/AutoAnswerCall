# AutoAnswerCall 1.18.1 — PCM 上行验证版

## 功能范围

本版**不实现** iOS 17.3 蜂窝通话上行音频注入。新开关默认关闭，开启后按系统来电已接通时的事件**离线解码前 2 秒音频**，不会激活 AVAudioSession、启动扬声器、改麦克风或注入 mediaserverd。不会获得来电方听到声音的证明。

源码增加：
- `AACPCMQueue.h`：固定容量 4096 帧 S16 mono 队列和数值统计（可 C 单测）。
- `AACPCMDecoder.h`：系统 `ExtAudioFile` 解码转换前 2 秒到 16kHz 单声道 S16 PCM，包含文件大小/帧数界限，不存储音频；这只是自选的测试格式，不是设备实际的蜂窝编码。
- `AACUplinkAdapter.h`：上行接口安全桩，固定返回不支持，零帧上行；严禁将普通本机播放当成上行。
- `Tweak.x`：已接通 + SpringBoard + 开关 + 来电规则合法时提交后台解码，日志 `UPLINK_PCM_PROBE`；这个模式禁用本机 `PlayLocal`。
- 设置与跨进程桥：新增 `UplinkPCMProbe`，默认关闭且同步到宿主。
- GitHub Actions：队列 C 测试、PCM 源码静态检查、macOS WAV→16 kHz PCM 转换冒烟测试。

## 使用
1. 在插件设置先导入并选择音频。开启插件、选对应规则，打开「上行PCM解码验证（不外放、不发送）」；建议暂时关闭旧的本机播放。
2. 由 iOS 系统自动接听，用同意测试的另一部手机拨打，接通后导出全量日志。
3. 期望 `UPLINK_PCM_PROBE result=decoded-only frames=... uplink=UNAVAILABLE sentFrames=0 remoteAudible=NO`。如果是 `decode-failed`，参考 `error` 和 `osStatus` 定位编解码问题。
4. **不要**把 `decoded-only` 当成远端成功；远端听到测试提示音才算上行注入成功。本版本没有实现该接口。

## 开发者资料与适用范围
- [Apple 添加合成语音到通话（iOS 18.2+）](https://developer.apple.com/documentation/AVFAudio/Adding-synthesized-speech-to-calls) — 可注入的官方方案，但不适用 17.3。
- [Apple Audio Converter Services](https://developer.apple.com/documentation/audiotoolbox/audio-converter-services) — PCM 采样率、格式转换；不代表蜂窝上行。
- [Apple AVAudioFile](https://developer.apple.com/documentation/avfaudio/avaudiofile) — PCM 解码和缓冲。
- [Apple Developer Forums 原生蜂窝通话访问答复](https://developer.apple.com/forums/thread/835552) — 第三方 App 不能通过 CallKit 随意取得 Phone.app 媒体流。
- [RootHide 开发文档](https://github.com/roothide/Developer) — 构建、权限及路径注意事项。
- [TrollRecorder](https://github.com/Lessica/TrollRecorder) — 录音方向开源参考，**录音并不等于上行音频发送**。
- [越狱社区 vCam 讨论](https://www.reddit.com/r/jailbreak/comments/1u1p7hp/vcam_virtual_cam_mic_for_ios_roothide_support/) — 仅开发者/社区声称可替换部分 App 麦克风；未验证普通蜂窝上行。

## 未验证／限制
本环境没有 Apple SDK/Theos/iOS 17.3 真机，也没有真实蜂窝上行接口，无法运行 Objective-C 的 iOS 代码或编译 .deb。macOS 上的解码冒烟测试由 Actions 在用户仓库运行。需要真机确认 `ExtAudioFile` 对所选 MP3 的兼容性。不要注入或改动系统音频守护进程。

## 录音服务参考
电话助手安装包包含 `CallAudioService` 二进制组件；它证明该插件采用了独立音频服务架构，但不能证明上行发送。
