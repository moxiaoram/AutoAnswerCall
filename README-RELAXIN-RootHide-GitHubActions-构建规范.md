# 影流助手 2.0.0：RELAXIN v0.4.8 / iOS 17.3 / RootHide 构建与自检规范

## 设备基线（以用户所提供截图为准）
- iPhone15,3（iPhone 14 Pro Max，A16）
- iOS 17.3 (21D50)
- RELAXIN v0.4.8，White List 白名单模式，RootHide 架构
- 抖音 40.8.0（目标 App 版本，实际私有 Hook 兼容性仍须真机测试）

## 重要区别
- 使用 RootHide Theos + `THEOS_PACKAGE_SCHEME=roothide`。
- 生成的 Debian 包必须 `Architecture: iphoneos-arm64e`；动态库本身可用 arm64 切片。
- 严禁普通 Rootless `/var/jb` DEB 冒充 RootHide 包。
- RELAXIN 白名单需启用抖音才能注入，打包通过不代表注入成功。

## GitHub Actions
- 将包含 `.github/workflows/build.yml` 的工程放入 GitHub 仓库。
- Actions -> Build RELAXIN RootHide DEB -> Run workflow；或推送代码触发。
- 运行 macos-15，准备 roothide/theos + theos/sdks，先静态检查，再 clean + package，后验证真实 .deb 内容。
- 校验不通过则工作流失败，不发布包。成功后下载对应 Artifact，并核对 SHA256SUMS.txt。
- 仅输出符合 RootHide 格式的包，禁止并列输出 Rootful/普通 Rootless 包以免误装。

## 本地 macOS（需要 Xcode 和 RootHide Theos）
```
python3 scripts/check_relaxin_source.py
make clean SCHEME=roothide
make package SCHEME=roothide FINALPACKAGE=1
python3 scripts/verify_relaxin_deb.py packages/*.deb
```

## 真机安装注入检查
1. 保持 RELAXIN 越狱状态；打开 RELAXIN / RootHide 应用白名单（White List），确保抖音在允许注入名单中。
2. 在 Sileo 中安装 RootHide 版本的 DEB，不要安装 Rootless/Rootful 版本。
3. 强制结束抖音再重新启动，测试设置入口和最小注入日志。
4. 注入仍失败时检查版本、目标 Bundle ID、依赖、崩溃日志，不要推断静态源码检查等于成功注入。
5. 若只注入某个克隆版/国际版而非当前抖音，还需核实应用实际 bundle identifier / executable，不能随意加 wildcard。

## 每次提交强制自检
- 源码改动后核对 `Makefile` 列出的新增 .m/.xm 文件存在，且已提交。
- 验证 `.github/workflows/build.yml` YAML 格式，确认步骤、构建方案、依赖与产物上传。
- 构建至少一次真实 RootHide DEB；不允许以压缩包结构检查代替编译。
- 从生成的真实 DEB 解包校验控制元数据、dylib、注入过滤器、架构、依赖、固件区间；保存构建日志。
- 无法在本地完成 Xcode/Theos 编译时，明确标注“静态检查通过，但 GitHub Actions 编译未验证”。
- GitHub Actions 编译通过后，仍需真机验证实际注入与业务 Hook。

## 官方参考
- https://github.com/roothide/Developer
- https://github.com/roothide/Bootstrap
- https://theos.dev/docs/commands
- https://theos.dev/docs/packaging
- https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts
