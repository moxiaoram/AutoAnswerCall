# AutoAnswerAudio v1.8.0 实验桥说明

该版本尝试利用 TrollRecorder 3.5.4 的 `TRCallMonitor` 内部活动 session 作为播放入口。请先保留现有版本和日志；本包仅是源码实验版，不是已经通过编译或通话测试的安装包。

构建需在支持 RootHide Theos 的环境中运行仓库内 `.github/workflows/build.yml`。构建成功后仍需验证：
1. `TRCallMonitor` 进程是否加载 tweak（日志中应出现 `v1.8.0 实验桥已在 TRCallMonitor 加载`）。
2. 自动接听后日志是否出现 `TRCallMonitor bridge 已调用 session 播放入口`。
3. 另一台电话是否确实听到音频。
4. 点击停止后音频是否停止、真实麦克风是否恢复。

若第一项没有日志，说明 helper 注入未生效；不要据此判断音频接口失败。
