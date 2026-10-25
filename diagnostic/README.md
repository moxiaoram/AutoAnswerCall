# 可选音频诊断探针（默认不随主插件加载）

此目录是单独的 Theos 工程，**不属于主插件默认构建**。它会 Hook `AudioUnitRender` 并在 `mediaserverd` / `audiomxd` 中记录 AudioUnit 信息。虽然不改写音频数据，但进入系统音频服务仍有稳定性风险。

## 构建

在已安装 RootHide Theos 的环境中：

```sh
cd diagnostic
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

该目录中的 `AACAudioProbe.plist` 仅在你主动构建并安装诊断包时使用。不要与主插件一起默认安装。先确认你知道如何通过包管理器卸载插件、并能处理 SpringBoard/音频服务异常。

## 日志

`/var/jb/Library/Application Support/AutoAnswerCall/AudioProbe.log`

## 限制

- 探针不实现电话上行音频注入。
- Hook 是否适用于你的 iOS 17.3 / RootHide 组合尚未验证。
- 它延迟读取 AudioUnit 指针，仍存在对象生命周期风险。出现音频卡顿、无声、通话异常或服务重启时，应立即卸载诊断包。
