# 抖音助手 1.6 - 长按面板直出、进度条与底栏文字下移

基于 1.5 完整源码继续修改，目标抖音 40.8.0。

## 修改概要

- 长按面板：不再等到原生控制器 `viewDidAppear` 后再 `present` 一层。改为在 `viewWillAppear` 构建数据，并在当前 `UIWindow` 中立即挂载自定义覆盖层；从 `viewDidLoad` 隐藏原生菜单视图以避免先闪出原生列表。
- 保留原有 action 模型与「查看原生面板」回退。数据尚未填充时先展示面板框架，待原生数据加载后刷新按钮；只有没有窗口可覆盖时才回退原生显示。退出/切换控制器时清理覆盖层。
- 红线：`DYYYVideoProgressDownOffset` 默认 **8pt**，整体移动 `AWEPlayInteractionProgressContainerView`，避免仅移动时间数字。
- 绿线：`DYYYTabTitleDownOffset` 默认 **6pt**，只移动 `AWENormalModeTabBarTextView`，不改变 TabBar 控件高度和点击区域。
- 设置入口：视频播放 → 视频进度条下移（点）；界面设置 → 底栏标题下移（点）。iOS 设置页和旧设置页均可修改，默认数值已通过 `registerDefaults:` 注入。

## 注意

原生控制器生命周期、播放页控件层次依赖 40.8.0 具体实现；当前缺少 Theos/iOS SDK，未能编译或真机测试。此版本为待测试源码。若长按无法弹出或弹出后交互异常，请记录日志，并优先把开关「长按直接弹出双列面板」关闭以恢复原生面板。
