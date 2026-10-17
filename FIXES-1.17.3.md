# 1.17.3 诊断增强版（尚未解决蜂窝电话自动接听）
依据用户归档：SpringBoard/InCallService `answerPaths=0`，`owner=(none)`；SpringBoard 扫描约 6000 节点未找到按钮。当前缺乏可验证的系统接听入口，不能声称自动接听已修复。

## 变更
- `AACButtonScan.h`：扫描时记录宿主、scene/window 数量，以及每个 window 的类、隐藏状态、透明度、层级、根控制器类型和尺寸；不记录私人来电号码。
- `Tweak.x`：延迟结束时记录宿主、UUID、配置有效性、通话状态及按钮扫描后的归属判断，便于分辨延迟/配置/控件路径。
- 版本号更新到 1.17.3。
- 没有放宽黑名单、重复点击保护或将本地播放器误报为电话上行。
## 限制
这不是自动接听功能的已验证修复。没有 Theos/iOS 真机环境，无法确认接听路径或上行音频。请在真实来电后导出全量日志，查找 `ANSWER_STAGE`、`BUTTON_WINDOW_ENUM`、`BUTTON_WINDOW`、`BUTTON_SCAN` 和 `owner=`。
