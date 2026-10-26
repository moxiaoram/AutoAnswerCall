# v1.8.1 — 单独的 TRCallMonitor 注入目标

## 为什么改

v1.8.0 的全局日志只有 SpringBoard 记录、没有 TRCallMonitor 记录。当前证据不足以证明 helper 进程加载了 tweak，因此不能继续把问题归到音频播放 API。

## 改动

- `AutoAnswerCall.plist` 只匹配 `com.apple.springboard`。
- 新增 `AutoAnswerTRBridge.plist`，只按 `TRCallMonitor` 可执行文件匹配。
- 构建两个 dylib：SpringBoard 自动接听端和 TRCallMonitor 桥接端。
- CI 检查新增的桥接 dylib 与 plist 是否进入 deb。

## 验证要求

本源码尚未在此环境中使用 Theos 编译。编译通过后安装，清空全局日志并触发一次来电：
1. 必须看到 SpringBoard 启动日志。
2. 必须看到 `TRCallMonitor` 进程启动日志 `AutoAnswerAudio v1.8.0 实验桥已在 TRCallMonitor 加载`（该日志字符串尚未随版本号更新）。
3. 若仍没有 helper 日志，说明单独 executable filter 仍未使该进程加载 dylib；下一步应先验证 helper 的真实进程名、代码注入范围与 RootHide 过滤规则。
4. 只有 helper 日志出现后，才继续判断通知、活动 session 和上行播放。

## 注意

此版本只针对诊断注入边界；不代表通话对方已经能听见音频，也不代表停止播放/恢复麦克风已经验证。
