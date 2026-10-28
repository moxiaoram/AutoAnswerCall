# 影流助手 2.0.8（RELAXIN / RootHide）

2.0.8 对比 1.7 修正三个 UI 回归：透明底栏只延伸播放器视图、不改写 Feed/Cell 高度；底栏标题平移不再被安全区算法压为 0；设置页优先复用抖音原有导航栈，避免空白中间页。

评论区毛玻璃现在递归清理评论列表中的不透明容器背景，并在 UITableView / UICollectionView 复用布局时重新应用。此版本仍需在抖音 40.8.0 真机上确认私有视图层级。

构建目标：RELAXIN 0.4.8、RootHide、iOS 17.3、arm64 dylib、iphoneos-arm64e DEB。严格链接继续禁止 `-Wl,-undefined,dynamic_lookup`。

运行静态检查：`python3 scripts/check_relaxin_source.py`、`python3 scripts/check_interaction_regression.py`、`python3 scripts/check_208_visual_native.py`、`python3 scripts/check_build_toolchain.py`、`python3 scripts/check_visual_effect_regression.py`、`python3 scripts/check_208_ui_regressions.py`。
