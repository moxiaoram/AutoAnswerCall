# v1.6.0 状态与验证清单

## 已写入源码
- SpringBoard 中基于 `TUCallCenter` 的实验性来电检测和 `answerCall:` 请求。
- 0–60 秒延迟设置、排除号码片段配置。
- 设置 Bundle 和 PreferenceLoader 入口。
- 从 Files 导入音频、复制到插件音频目录、列表管理、选择、试听/停止试听、删除。
- 主插件与设置页使用 `com.autoanswer.call` 配置域。
- 可选诊断探针独立放在 `diagnostic/`，不进入主插件默认构建。

## 本轮静态检查
- `AutoAnswerCall.plist` 和设置入口 plist 的结构可解析。
- 设置 `Root.plist` 可解析，控制器中有对应的按钮方法。
- `ExcludedNumbers` 已与主插件逻辑对齐，并兼容旧的 `Whitelist` 键。
- 主插件 Makefile 只构建 SpringBoard tweak 与设置 bundle，不会默认安装音频服务探针。

## 尚未验证
- Theos 编译和 DEB 生成。
- 设置页在 iOS 17.3 上显示、保存和音频文件操作。
- `TUCallCenter.incomingCall`、`answerCall:` 在当前系统与进程中是否有效。
- 实际号码属性读取。
- 真实电话上行音频注入、停止后麦克风恢复、保持通话、原生通话 UI 按钮替换。

## 重要限制
本工程目前不能实现“对方听到导入音频”。主设置页的试听是本机试听。上行注入代码尚未实现，不能将此源码包当成已完成的最终功能版。
