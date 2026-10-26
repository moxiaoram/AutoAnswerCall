# AutoAnswerAudio 1.6.0 源码包（RootHide / iOS 17.3 研究版）

## 重要状态说明

这是**完整工程源码包**，不是已经验证的完整功能成品。源码已包含设置页、音频文件库管理、自动接听尝试和可选音频诊断工程，但没有声称以下功能已实现：

- 普通蜂窝电话自动接听在 iOS 17.3 真机上成功运行；
- 把导入的音频真正送入电话上行链路；
- 停止注入后恢复麦克风并保持通话；
- 把系统通话界面的“添加通话”按钮替换为停止按钮。

**音频上行注入仍未实现。** 设置页的本机试听只会让本机播放声音，不会自动让电话另一端听到。

## 工程结构

- `Tweak.x`：SpringBoard 中的实验性 `TUCallCenter` 来电检测和 `answerCall:` 请求。
- `AutoAnswerCall.plist`：仅注入 `com.apple.springboard`。
- `Preferences/`：系统设置页、音频导入/复制、选择、试听/停止试听、删除和设置保存。
- `layout/Library/PreferenceLoader/Preferences/autoanswer.call.plist`：设置页入口。
- `diagnostic/`：独立的可选音频诊断探针工程。默认主插件构建不包含或加载它。
- `.github/workflows/build.yml`：GitHub Actions RootHide Theos 构建工作流。

## 当前设置项

- 启用插件
- 来电自动接听（实验开关，默认关闭）
- 接听延迟（0–60 秒）
- 不自动接听的号码片段（逗号分隔）
- 导入音频
- 管理 / 选择音频
- 试听 / 停止试听
- 删除当前选中音频
- 当前音频路径

音频文件复制到 `/var/mobile/Library/AutoAnswerAudio/`，配置域为 `com.autoanswer.call`。

## 构建主插件

将整个 `AutoAnswerAudio` 目录放入 GitHub 仓库根目录，在已配置 RootHide Theos 的环境运行：

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

也可以推送到 GitHub 后，在 Actions 中手动运行 `Build AutoAnswerAudio (RootHide)`。当前工作环境没有 Theos，因此此源码包尚未在本轮本地编译；只有 Actions 的真实构建结果才能确认是否可编译。

## 可选诊断探针

请阅读 `diagnostic/README.md`。它是独立包，会进入 `mediaserverd` / `audiomxd` 并 Hook `AudioUnitRender`，存在系统音频稳定性风险；不要把它当成普通用户必装组件。

## 安全测试建议

1. 先只安装主插件，确认设置页能出现、音频导入/选择/试听/删除工作正常。
2. 自动接听默认关闭；先用非重要测试电话验证，不要用于紧急电话。
3. 记录 `/var/jb/Library/Application Support/AutoAnswerCall/AutoAnswerCall.log`。
4. 在确认主插件稳定之前，不要安装诊断探针。
5. 任何音频异常或系统服务崩溃时，立即卸载测试包。

## 已知限制

- `TUCallCenter` 和 `answerCall:` 属于私有接口，系统版本、调用进程和权限可能影响行为。
- 号码读取依赖当前系统 `TUCall` 对象实际暴露的属性；需设备日志确认。
- 音频注入、注入停止、麦克风恢复和通话 UI 改造没有实现。
- 未经编译、安装和真机测试的代码不能视为功能已验证。

## 全局诊断日志

Tweak（SpringBoard）和设置页共用日志文件：
`/var/mobile/Library/AutoAnswerAudio/AutoAnswerAudio.log`

在设置页点击“查看 / 复制全局日志”，可查看最近日志、复制到剪贴板或清空日志。每条记录包含时间、进程、PID、源文件、行号和函数名。复现问题后请复制日志发送，以便定位究竟卡在来电检测、接听调用、播放器初始化、上行混音选择还是停止流程。
