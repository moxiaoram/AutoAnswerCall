# AutoAnswerAudio v2.1.3 — 优先原生 Hook “添加”按钮

## 本版实现

- **系统原生控制按钮（优先）**：在 `InCallService` 的 `PHAudioCallControlsViewController` 存在且 `titleForControlType:`、`imageForControlType:`、`controlTypeTapped:forView:` 签名匹配时，使用 `MSHookMessageEx` 接管这些方法；动态查找原文为“添加 / 添加通话 / Add / Add Call”的 control type，不写死枚举值。标题改为 **停止**，图标改为 `stop.fill`，点击事件改为给插件发送停止通知，不再执行系统的“添加通话”动作。按钮保留苹果原有视图、直径和布局，不绘制一个悬浮按钮覆盖它。
- **系统禁用“添加”时**：如果存在 `controlTypeIsEnabled:` 且签名匹配，则仅对插件启用时识别到的原生按钮返回 YES；其他原生控件全部保持原始处理。若用户在设置中关闭插件，原生控件继续表现为“添加”。
- **旧版兼容**：如果系统没有相同控制器或方法签名不匹配，就保留 v2.1.2 使用视图树匹配“添加”的兼容实现（此模式仍属于覆盖实现，并非原生 Hook）。日志会记录选择的路径。
- **拨号盘不遮挡**：InCallService 每次扫描都报告拨号盘状态；SpringBoard 的后备悬浮按钮仅在收到最新 **拨号盘已隐藏** 信号后才允许出现。失去同步信号时默认隐藏，避免遮挡数字 8。插件不会主动隐藏系统拨号盘。
- **停止=人工接管**：触发 `com.autoanswer.call.stopUplinkPlayback`，SpringBoard 执行 TTS 终止、禁止下一轮播放、请求 TRCallMonitor 停止并尝试把插件静音的通话麦克风恢复；**不会主动挂断通话**。
- **保留 2.1.2 的免提路由中断恢复逻辑**，但音频是否真正持续上行需要真机验证。

## 重要说明

本次直接 Hook 的接口出处为旧版 InCallService 逆向头文件：
https://gist.github.com/joemerlino/31bf8d0f1446c9ad6d278cd84b815049

这些是非公开接口，**未确认 iOS 17/RootHide 真机是否仍有同名类及方法**。本源码为 **待编译、待真机验证** 的实验修改，不是保证可以用的 `.deb`；没有 Theos/iOS SDK 的环境无法产出和验证安装包。安装测试前应备份原版，做好禁用插件或安全模式恢复准备。

## 真机排查关键日志

1. `已安装 PHAudioCallControlsViewController 原生控件 Hook`：系统原生接口已找到、Hook 已尝试安装。
2. `原生通话按钮已识别：添加(type=...) -> 停止`：原生控制类型识别完成。
3. `原生停止按钮点击`：用户按下了替换后的原生按钮。
4. `原生按钮类 ... 不存在` / `方法缺失或签名不符` / `找不到 MSHookMessageEx`：走兼容视图扫描路径。
5. `上行：收到停止请求` / `麦克风：已恢复`：SpringBoard 内的停止和恢复逻辑触发（能否真正恢复仍应让对方验证）。

## 验收重点

- [ ] 在通话主页面左下角，将“添加”变为“停止”；图标、圆形直径和其他系统按钮一致。
- [ ] 进入数字键盘后 0-9/*/# 完整可见，不自动切回主控制页面。
- [ ] 点击免提时上行声音不中断，或中断后能按原恢复逻辑重新播放。
- [ ] 点击“停止”后对方听不到插件的录音/朗读内容，并可以听到人工讲话；电话不挂断。
- [ ] 系统“静音”、 “免提”、 “拨号键盘”、 “结束”仍能正常使用。
- [ ] 如果关闭插件开关，系统“添加”功能不被劫持。

## 构建方法

在安装 Theos、iOS 17 SDK 与 RootHide 工具链后执行：

```sh
cd AutoAnswerAudio
make clean
make package THEOS_PACKAGE_SCHEME=roothide
```

本环境没有 Theos 和 iOS SDK，不能声称已完成编译或真机测试。
