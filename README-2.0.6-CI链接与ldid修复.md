# 影流助手 2.0.6：修复框架链接与 ldid 缺失

本版从 2.0.5 完整源码修改，只处理构建配置及版本元数据，不声称修复其他未验证的 UI 行为。

## 修复内容

- 旧 Makefile 在 `_LDFLAGS` 中错误放入裸框架名：`UIKit AVFoundation ...`。现在改用 `$(TWEAK_NAME)_FRAMEWORKS`。`AVFAudio` 用 `$(TWEAK_NAME)_WEAK_FRAMEWORKS`。`_LDFLAGS` 只保留 `-Wl,-undefined,error`。
- GitHub Actions 在构建前使用 Homebrew 安装 `make ldid xz dpkg`，并对 `ldid`、`dpkg-deb` 和 `gmake` 运行存在性检查。
- 增加 `scripts/check_build_toolchain.py` 防止以上两类问题重新进入分支；同时保留原有 `check_relaxin_source.py` 和 DEB 内 Mach-O 校验脚本。
- 持续使用 RootHide Theos、`SCHEME=roothide`、`ARCHS=arm64`、`DEB_ARCH=iphoneos-arm64e`、严格符号链接，不加入 `dynamic_lookup`。

## GitHub Actions

执行 **Build AwemeVision RELAXIN RootHide DEB**，使用 `startup_mode=full`、`legacy_loader_name=true`、`probe_only=false`。先跑 3 个源码审计，再安装工具链并构建。如果严格链接出现 `Undefined symbols`，应修正代码或明确链接合法框架，不要恢复 `dynamic_lookup`。

## 验证界限

在 Linux 容器中可做 YAML、Python 脚本及静态回归检查，无法替代 macOS + Xcode + RootHide Theos 编译及手机注入测试。
