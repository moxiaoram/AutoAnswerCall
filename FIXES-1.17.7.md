# AutoAnswerCall 1.17.7 — 修复记录

## 归档(3).zip 的定位

2026-10-17 的 SpringBoard 日志显示 `ringingSeen=1 policyEligible=0 companionEnabled=1 singlePlaybackSwitch=1`，导出配置中 `Mode=1`、`PlayAudio=true`、排除名单空。1.17.6 的响铃路径使用 `Allowed()`，调用 `AACShouldRequest` 并要求 `mode==2`，因此模式 1 在播放器打开前被拒绝。

## 代码变动

1. AACPolicy.h：新增独立的系统接听后播放规则。模式 1 = 全部来电允许播放；模式 2 = 有效名单之外允许播放（名单存在但号码未知时不播放）；未知模式、出站、已结束、关闭策略不能播放。
2. Tweak.x：响铃时按播放规则登记，接通时对当前 `CXCall` 和当前配置重新判断；保留本宿主已看到来电响铃的要求，避免在插件中途载入时对已经通话中的电话突发播放。
3. Tweak.x：原先只有 mode=2 才可接听的 `Allowed()` 仍独立保留在旧接听路径，不再被系统接通后的播放路径重用。
4. Tweak.x：只读日志输出当前 `AVAudioSession` 类别、模式、输出端口，帮助诊断本机静音或路由问题；不修改蜂窝通话音频会话。
5. 设置页调整模式文案，明确这是播放规则，而不是控制 iOS 辅助功能的全局自动接听开关。
6. 新增纯 C 播放资格单元测试、结构回归检查，并更新 CI 版本为 1.17.7。

## 仍需验证

此代码尚未在 iOS 17.3 / RootHide 设备上编译和真机验证。InCallService 中的「停止播放」按钮依旧依赖对应窗口和共享播放状态。`AVAudioPlayer` 不会把音频直接注入对方听到的通话上行。请安装后导出完整日志，重点查看：`SYSTEM_ANSWER_TEST ringing`、`SYSTEM_ANSWER_TEST connected`、`AUDIO_TEST stage=open`、`AUDIO_TEST route`、`AUDIO_TEST result=started`、`MANUAL_HANDOFF`。
