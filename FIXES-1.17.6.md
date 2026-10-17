# AutoAnswerCall 1.17.6：系统接听兼容测试版（单开关）

依据 `归档(2).zip`：`SystemAnswerPlaybackTest=False`、共享配置 `systemPlaybackTest=missing`，通话日志 `testEnabled=0`、`startEligible=0`，所以前版从未尝试播放；InCallService 按钮必须等待播放状态为 playing，自然也没有显示。

## 变更

- 保留 iOS 系统负责自动接听。插件策略 Enabled=YES 时，放弃无效的蜂窝接听提交路径，仅观察来电。
- `PlayAudio` 是唯一的播放开关，设置页名称“系统接听后播放本机音频（含停止按钮）”；移除第二个重复开关。旧 `SystemAnswerPlaybackTest` 值仍可读取/导出，但**不再影响运行逻辑**。
- 接通时输出 `companionEnabled`、`singlePlaybackSwitch`、`policyEligible`、`ringingSeen` 和 `startEligible`；不符合播放条件时记录明确原因。
- InCallService 接通但没有播放状态时，记录 `MANUAL_HANDOFF no-button ...`，以区分没有音频与按钮窗口创建失败。
- 保留 UUID 限定的停止操作，点按钮不会挂断通话。

## 真机使用

1. 设置 → 辅助功能 → 触控 → 音频通话方式 → 自动接听通话：开启。
2. AutoAnswerCall 设置：启用插件策略 ON、**系统接听后播放本机音频（含停止按钮） ON**、选中有效 MP3，确保未启用“立即停止”的锁存状态（可点击“恢复插件策略”）。
3. 编译安装后，重启 SpringBoard / 相关进程后再拨入测试来电。导出全量日志并检索 `SYSTEM_ANSWER_TEST`、`AUDIO_TEST`、`MANUAL_HANDOFF`、`CONFIG_DIAG`。

## 限制

- 这是静态修复，未在 iOS 17.3 / RootHide 真机验证。
- `AVAudioPlayer` 仅是设备本地音频输出，**不等于让来电者听到录音**；当前项目未实现蜂窝通话上行音频注入。
- InCallService 顶层按钮窗口能否显示仍需真机验证，若该进程不存在/不可见、通话界面由其他进程承载，按钮可能无法出现。
- 系统自动接听是全局功能，插件白名单只能约束播放，不能限制 iOS 系统接听。
