# v1.7.3 XPC 探测诊断版

- 新增对 TrollRecorder 二进制中观察到的 `wiki.qaq.trapp.xpc` 的短时连接可达性探测。
- 只记录 NSXPCConnection 中断/失效；不发送未经验证的播放 RPC。
- 不再把 SpringBoard 进程内找不到 `TRAudioPlayer` 当作唯一诊断结果。
- 此版本不代表已实现通话上行注入，必须安装后查看全局日志判断服务是否可连接。
