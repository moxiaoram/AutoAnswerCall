# 影流助手 2.0.2 — 以最后已知可注入的 1.7 为基准

> **注意**：这是对源码与构建条件的回归排查。由于没有用户手机上的实际安装 DEB、设备侧 Loader 日志，也没有 Theos / iOS SDK，本项目不能凭静态检查断言已经真机注入成功。

## 设备和目标
- 设备：iPhone15,3 / iOS 17.3 (21D50)
- 越狱：RELAXIN 0.4.8 / RootHide / White List
- 抖音：40.8.0，Bundle ID **com.ss.iphone.ugc.Aweme**（用户设备实拍）
- 独立包：**com.local.awemevision.relaxin**。故意与旧版 `com.huami.dyyy` 冲突，不会作为旧包升级。

## 源码实测差异（旧 1.7 vs 新 2.0.1）

| 项目 | 已生效的 1.7 | 未正常注入的 2.0.1 | 2.0.2 默认处理 |
|---|---|---|---|
| 文件名 | DYYY.dylib / DYYY.plist | AwemeVision.dylib / AwemeVision.plist | **先恢复 DYYY 文件名**，独立 Debian 包身份不变 |
| 注入过滤器 | 仅 Bundles | Bundles + Executables=Aweme | **恢复仅 Bundles** |
| 主构造函数默认组 | 没有全局 `%init;` | 从 1.8 新增 `%init;` | **兼容启动不执行全局 `%init;`**，`full` 才执行 |
| 架构与越狱 | 当年源文件默认 rootful，支持 `SCHEME=roothide` | RootHide iphoneos-arm64e | **保留正确 RootHide 构建** |
| 链接 | 常规 | `-undefined dynamic_lookup` | 全功能保留以兼容已成功编译的 CI，探针关闭此参数 |
| 包 ID | `com.huami.dyyy` | `com.local.awemevision.relaxin` | 保留**新包 ID**，避免老更新渠道识别为升级 |

**为什么这么改**：现有数据无法证明是「文件名/白名单」还是「1.8 后全局 Hook 导致进程加载后异常」。兼容配置一次性消除这两处相对于 1.7 的差异，便于恢复可验证的加载行为。`%init;` 会影响默认组中的大量功能，禁用它后不是所有新功能都能运行。先确认加载，再测试 `full`。

## GitHub Actions 编译

在 **Actions → Build AwemeVision RELAXIN RootHide DEB → Run workflow** 中：

1. **第一次**使用 `startup_mode=compat`、`legacy_loader_name=true`、`probe_only=false`。默认设置已经如此。
2. 如果没有任何加载迹象，再试 `probe_only=true`，其余不变。探针仅验证动态库加载，不会显示插件设置。
3. 兼容版已经能注入后，才测试 `startup_mode=full`。如果只有 full 失败，说明问题在默认 Hook 初始化范围而不是包名/过滤器。
4. 如果怀疑 RELAXIN 白名单与动态库文件名有关，可将 `legacy_loader_name=false` 与旧名构建对比（每次只能安装其中一个）。

脚本会分别生成唯一 DEB，附带 `SHA256SUMS.txt` 与 `BUILD_METADATA.txt`。不要混装 `com.huami.dyyy` 或同包名不同文件名的版本。

### 命令行

```bash
# 最保守、推荐的首轮复测
make clean SCHEME=roothide AWEMEVISION_STARTUP=compat LEGACY_LOADER_NAME=1
make package SCHEME=roothide AWEMEVISION_STARTUP=compat LEGACY_LOADER_NAME=1 FINALPACKAGE=1

# 无法注入时的最小加载探针
make clean SCHEME=roothide AWEMEVISION_STARTUP=compat LEGACY_LOADER_NAME=1 PROBE_ONLY=1
make package SCHEME=roothide AWEMEVISION_STARTUP=compat LEGACY_LOADER_NAME=1 PROBE_ONLY=1 FINALPACKAGE=1

# 只有确认兼容版已正常加载以后再试完整 Hook
make clean SCHEME=roothide AWEMEVISION_STARTUP=full LEGACY_LOADER_NAME=1
make package SCHEME=roothide AWEMEVISION_STARTUP=full LEGACY_LOADER_NAME=1 FINALPACKAGE=1
```

## 注入结果如何判断

1. **抖音完全退出**，从多任务后台划掉，安装包后重新打开。
2. RELAXIN 的 **White List** 必须允许抖音 `com.ss.iphone.ugc.Aweme` 注入插件。这个设置无法从源码代替执行。
3. 到抖音沙盒目录下检查 `Library/Caches/AwemeVision-early-load-2.0.2.log`：
   - **存在**：至少说明动态库已进入构造函数。若设置没出现，继续查 Hook 和启动过程。
   - **不存在**：可能是动态库从未加载、加载前依赖/签名出错，或文件无法写入；不能单凭缺失证明注入框架未运行。
4. `Library/Caches/AwemeVision-injection-2.0.2.txt` 由主队列写入，出现后说明主线程已经运行到探针任务。日志也可搜索 `[AWEMEVISION-INJECT]`。
5. 若 PROBE 加载但兼容 FULL 不加载，检查非探针源文件的链接依赖、崩溃报告和 dyld 日志。
6. 若 PROBE 也不加载，先排查实际 DEB 文件列表、RELAXIN 白名单、RootHide 安装路径和系统注入开关。

**本次仍无法通过静态源码确定的项目**：用户实际安装的 `.deb` 数据、是否成功写入磁盘、RELAXIN 对抖音的注入授权、dyld 载入与崩溃日志。这些必须用设备数据验证。

## 持续构建约束

- 保留手动克隆 `roothide/theos`、`theos/sdks`，不得恢复容易失败的 `beerpiss/theos-action@v1`。
- 保留此前 `dataArray` 声明、动态长按管理器引用、单独 Logos Swift 注入组和 `dynamic_lookup` 的编译修复。
- 所有构建先 `make clean`，检查 `logos.pl`，再检查真实 DEB 包架构、文件名、过滤器。
- 输出必须明确 **静态检查 ≠ 已编译 ≠ 已注入**。
