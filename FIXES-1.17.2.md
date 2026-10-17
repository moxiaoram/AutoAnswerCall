# AutoAnswerCall 1.17.2：静态修复与真机待验证项

## 截图及历史诊断表明的阻塞

- SpringBoard、InCallService 的探测通知到达；MobilePhone 在截图时未到达。MobilePhone 可能未运行/休眠/未注入或通知不可见，不能由这张截图确定根因；现代 iOS 来电界面通常由 InCallService/SpringBoard 参与，而不是 MobilePhone。
- 先前设备记录表明部分宿主 `answerPaths=0`，公开 CXAnswerCallAction 返回未授权（CallKit transaction error code 1）。发出 UIKit 按钮事件不能证明电话确实接通。没有这一设备的触发时日志，仍无法证实真实接听入口。
- 旧 `AACMayAutoplay` 需要从未设置的 `ownershipConfirmed`，并在任何 `hasConnected` 后无条件抑制音频，故自动播放逻辑不可能满足。
- 导入音频只存储于 Settings 的 Application Support；宿主可能读不到音频和 CFPreferences 配置。

## 本版已修改

1. `AACConfigBridge.h` 创建 `/var/mobile/Library/Application Support/AutoAnswerCall/runtime-config.plist`，设置启动/开关/模式/排除名单/秒数/音频选中时尝试发布。该路径仅为候选，无法保证各宿主的沙盒可访问。读不到会打印 CONFIG_DIAG，原生配置不可读则安全禁用。
2. 选中的本地音频最多 5 MB，复制到共用候选目录。文件读取、复制、配置保存均有错误处理；失败时不声称其它宿主能播放。
3. 原来永远不可能到达的播放条件被替换为：**本宿主已实际发送按钮事件，随后才由 CXCallObserver 观察到连接，且尚未尝试播放过**。按 UUID 限制最多一次；未做按钮操作的人工/系统连接不触发。
4. 本地 `AVAudioPlayer` 会记录是否打开/开始/失败，在通话结束时停止。**AVAudioPlayer 只是本机音频输出，绝不表示来电人能听到音频。通话上行（虚拟麦克风/RemoteIO/Telephony capture）在本项目中未实现。**
5. MobilePhone 不响应 probe 不是自动接听的充分失败解释：`CONFIG_DIAG` 分别打印宿主读取配置/音频的结果，结合 BUTTON_SCAN / BUTTON_TAP / CXCallObserver 才能定位阶段。
6. 仍保留上版的界面灰色 footer 去除、黑名单按钮防误点、单 UUID 防双击和 RootHide GitHub Actions。

## 未验证及潜在风险

- 没有 RootHide iPhone 上的编译/运行环境，不能证明 UI 控件模拟点击确实触发真实蜂窝通话接听。
- `CXCallObserver.hasConnected` 不包含“由哪个宿主接听”的归因：即使自动点击曾发出，也有可能是人工/系统随后接通，故本地播放仍有歧义。
- 共用目录权限可能因机型/沙盒设置而不同；关闭插件/编辑排除名单后应查看 Settings 的同步告警与宿主 `CONFIG_DIAG`，否则旧配置可能仍被缓存。
- 不能在当前工程内通过简单切换 `AVAudioSession` 将 `AVAudioPlayer` 声音注入电话上行；需要独立针对目标 iOS 版本验证的电话音频路由实现。

## 真机复测方式

1. 用 GitHub Actions 编译为 `iphoneos-arm64e`，安装/重载注入宿主。
2. 打开设置页确认没有“共享配置未建立”提示，并重新选择要播放的音频；配置里选择允许的接听模式/等待秒数。
3. 真实来电等待秒数到期后导出“分享全部运行日志”，重点看 `CONFIG_DIAG`、`Scheduled`、`接听归属判定`、`BUTTON_SCAN`、`BUTTON_TAP`、`Connected`、`LOCAL playback`。
4. 手机本地听到音频和对方听到音频是两个不同测试：最后一项本版没有实现。

测试类型：源码静态回归、C 逻辑单元测试、7z 完整性；未执行 iOS 真机编译及蜂窝通话测试。
