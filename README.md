# 影流助手 2.0.11（RELAXIN / RootHide）

2.0.11 针对 1.7 与 2.0.8 的位置和导航回归：进度条与底栏标题在 setTransform 和 layoutSubviews 中维护原生基准变换；透明底栏只尝试延伸播放器/交互视图，不更改 Feed/Cell 高度；设置页统一使用单个独立模态导航栈，删除空白临时控制器。

评论区毛玻璃现在递归清理评论列表中的不透明容器背景，并在 UITableView / UICollectionView 复用布局时重新应用。此版本仍需在抖音 40.8.0 真机上确认私有视图层级。

构建目标：RELAXIN 0.4.8、RootHide、iOS 17.3、arm64 dylib、iphoneos-arm64e DEB。严格链接继续禁止 `-Wl,-undefined,dynamic_lookup`。

运行静态检查：`python3 scripts/check_relaxin_source.py`、`python3 scripts/check_interaction_regression.py`、`python3 scripts/check_208_visual_native.py`、`python3 scripts/check_build_toolchain.py`、`python3 scripts/check_visual_effect_regression.py`、`python3 scripts/check_208_ui_regressions.py`。

新版修改明细见 [README-2.0.11-界面位置与退出修复.md](README-2.0.11-界面位置与退出修复.md)。
