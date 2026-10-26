# AutoAnswerAudio v1.8.1 — 下一步验证版

本版本针对 v1.8.0 日志中只有 SpringBoard、没有 TRCallMonitor 记录的问题。它将两个注入目标拆成两个独立 tweak/filter：`AutoAnswerCall.dylib` 仅匹配 SpringBoard，`AutoAnswerTRBridge.dylib` 仅匹配 `TRCallMonitor`。

## 先做什么
1. 上传本目录中的源码到 GitHub 仓库根目录（保留 `.github/workflows/build.yml`）。
2. 运行 Actions 的 `Build AutoAnswerAudio (RootHide)`。
3. 只有 Actions 成功且 artifact 中同时包含两个 dylib 和各自 plist，才安装。
4. 安装后注销/重启目标进程，清空全局日志，测试一次来电。
5. 查看是否出现 `TRCallMonitor` 进程日志。

如果没有 helper 日志，请把 Actions 成功/失败页面及安装后的全局日志发回来；不要继续反复测试播放，因为请求接收端还未证实加载。

这仍是实验源码，未在当前环境编译或真机验证。音频上行与停止后恢复真实麦克风仍未确认。
