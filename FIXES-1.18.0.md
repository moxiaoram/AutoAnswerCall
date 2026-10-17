# 1.18.0 修改摘要（静态诊断版）

本版不复制电话助手的代码或授权逻辑。对其二进制做静态比对发现 `CallAudioService` 包含 `AudioQueueNewInput`、`initTapInternalWithFormat:PIDs:` 和 `SandyXpc` 等音频采集/IPC 符号，无通话上行注入成功的证据。

## 修复
1. InCallService 有界视图清单新增可见控件数量、控件类名与尺寸、父类型；不记录个人隐私。
2. `hostreport.summary` 加入最新界面清单和按钮判定结果，让设置端更容易看到阻塞点。
3. 播放开始先公布 `starting`；只有 `currentTime > 0.1` 才公布 `playing`。发生音频中断开始通知后停止，不继续保留假状态。
4. 设置启动信息与系统接听模式保持一致。

## 未完成
- iOS 17.3 活动通话界面的真实「添加」控件类及父视图仍需真机查明。
- 蜂窝通话上行播音接口未知；本版本没有实现来电方能听到 MP3。
- 无 RootHide Theos/iOS 真机编译环境，本地 C 和静态检查不代表能在手机安装/运行。
