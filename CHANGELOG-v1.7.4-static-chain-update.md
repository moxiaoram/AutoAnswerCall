# v1.7.4 静态调用链证据更新

- 将 TrollRecorder 3.5.4 中发现的播放请求 selector 写入运行日志，便于后续对照反汇编结果。
- 明确 `TRAudioPlayer` 是 TrollRecorder 的独立辅助可执行文件；不再尝试在 SpringBoard 内用该类初始化本地播放器。
- 保留 `wiki.qaq.trapp.xpc` 的诊断性连接探测，但不发送未经确认的远程调用。
- 继续保留来电检测/自动接听和偏好设置代码。
- 本版不是已完成的上行音频注入版本：XPC host 标识、远程方法签名和停止/恢复麦克风流程仍未确认。
