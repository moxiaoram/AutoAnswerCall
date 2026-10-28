# 影流助手 2.0.12：底栏透明回归原因

## 比较范围

本次可用的最早完整源码包为 **1.1**；没有名为 1.0 的源码包。额外对比了 1.7（此前可正常实现透明显示）与 2.0.11。

## 核心差异

1. 1.1 在 `AWENormalModeTabBar` 的 `layoutSubviews` / `setHidden:` 中直接隐藏 `skinContainerView`、`_UIBarBackground` 与和底栏同高度的绘制视图。
2. 1.7 增加 `DYYYFullScreenOrClearTabBar()`，把 `DYYYHideBottomBg` 也视为需要视频延伸到屏幕底部的条件，因此只有隐藏底栏背景后面才会出现视频画面，而不是露出宿主的黑色底色。
3. 2.0.11 在 `DYYYFullScreenOrClearTabBar()` **开头**加入 `if (DYYYStableFeedLayoutEnabled()) return NO;`，而防错位模式默认开启。这样在透明开关开启时，底栏自身仍可隐藏背景，但播放器/进度/部分视觉 Hook 不再执行原有的全屏显示分支，背景只剩黑色宿主画面。之前分散增加的播放器局部高度补偿无法覆盖所有进度、渲染和控制器布局分支。

## 2.0.12 的变更

- 恢复 1.7 的 `DYYYFullScreenOrClearTabBar()` 语义，让透明开关再次触发需要的视频下层绘制链。
- **保留** 1.9 之后的 Feed / Cell 防错位处理，不恢复危险的整页取整：`AWEDiscoverFeedTableView` 稳定模式仍直接使用原生布局，`AWEAwemeDetailTableView` 仍禁止倍数屏高修正。`AWEConcernCellLastView` 旧版重复平移也仅在主动关闭稳定模式时生效。
- **保留** 当前 RootHide 严格链接、长按边缘倍速和评论毛玻璃相关实现。
- 增加 GitHub Actions 代码回归测试，防止未来又将稳定模式放进视频显示开关，造成同样故障。

## 检查与限制

这次完成的是静态源码修复和 CI 预检。没有在 iPhone15,3 / iOS 17.3 / RELAXIN 上编译、注入或目测确认。若播放器仍使用自身内部黑底而不渲染到底部，就需要实际视图树或真机运行日志才能定位，不应继续无差别隐藏父视图。

安装前卸载/覆盖旧版后彻底关闭并重开抖音；分别检查推荐页、图文页、评论关闭后、连续翻页。不要把评论弹层的灰色背景误判成底栏背景。
