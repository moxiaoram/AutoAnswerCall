# 2.0.8：对比 1.7 修复底栏、标题、评论区与设置返回

## 修复点

1. 保留 `DYYYStableFeedLayout` 对 Feed/Cell 高度的保护，但在透明底栏启用时，允许播放器视图仅在与父视图高度差等于底栏高度时延伸。没有重新启用旧版对整张 Feed 表格按屏高取整的做法。
2. 标题偏移恢复 1.7 的实际行为：限制用户输入范围 `-12..18 pt`，不再根据当前 safe-area 剩余距离把下移值变为 0，同时保存/恢复视图原始 transform。
3. 评论毛玻璃递归清除评论面板内普通容器、列表、cell、contentView 的不透明背景与 layer 背景；UITextField/按钮、文字、图片、UIVisualEffectView 本身不被清空。UITableView 与 UICollectionView 布局复用时重新应用。
4. 插件设置优先 push 到打开它的抖音导航栈；只有入口没有导航控制器时才建立独立模态导航。关闭时只移除插件设置页，不再 popToRoot 把导航栈带到空白中间页。
5. 严格链接、RootHide 打包配置与 1.7 的 `DYYY.dylib` / Bundles-only 注入过滤器保持不变。

## 自检边界

本地脚本仅验证源码结构、参数与防回归条件。最终仍需 GitHub Actions 真正编译 DEB，并在 iOS 17.3 / 抖音 40.8.0 / RELAXIN 0.4.8 真机上确认私有视图层级、透明底栏实际透出视频、评论列表滚动后毛玻璃和单次返回行为。
