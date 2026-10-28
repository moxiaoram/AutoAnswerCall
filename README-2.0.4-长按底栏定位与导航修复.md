# 影流助手 2.0.4 — 视频长按、透明底栏、偏移与设置退出

适配目标：iPhone15,3 / iOS 17.3 / RELAXIN 0.4.8（RootHide 白名单）/ 抖音 40.8.0。

## 修改原因与处理

1. **长按菜单**：原代码只在 Feed Cell 的 `setModel:` 挂长按手势，Cell 复用或某些版本绕过此 setter 时会失效。现在补充两个 Cell `layoutSubviews` 入口以及 Feed UITableView 级兜底识别器；识别器分别约 0.30 / 0.28 秒，允许与正常滚动同时识别。已修正 Native controller 消失时误移除 Feed 手势先显示的覆盖面板。
2. **底栏背景**：保留稳定 Feed 布局，清理 TabBar 自身、skin 和直接父容器中具有背景特征的视图，包括符合尺寸约束的空背景视图。不会擅自改写整屏 Feed 的 frame；如果视频渲染层本身没有延伸到导航栏下方，背景即使透明也可能露出播放器外原底色，须以设备画面确认。
3. **进度条和底栏标题**：默认从上版 6/3 点调整到 10/6 点，放宽原先的 12/8 点限制；使用一次性迁移标记修正安装过旧版的设备配置（已有非默认自定义值不改）。仅做视图内部变换，不改变视频 Cell 尺寸。
4. **设置退出**：原来把设置页 push 到抖音内部导航，容易在第一次退出时露出空白页。现在插件有自己的 full-screen UINavigationController，根页的关闭/左侧边缘右滑直接 dismiss；二级页面返回上一级。分类回调全部转发至插件自己的导航栈。

## 构建与验证

- GitHub Actions 的 `AWEMEVISION_STARTUP=full`、`LEGACY_LOADER_NAME=1`、`SCHEME=roothide` 保持不变。
- `-Wl,-undefined,error` 保留，不添加任何 `-undefined dynamic_lookup`。
- 本地静态审计：`python3 scripts/check_relaxin_source.py`、`python3 scripts/check_interaction_regression.py`、`python3 scripts/audit_settings_bindings.py`。
- CI 必须通过 Logos 预处理、RootHide 编译，以及对 **实际 DEB** 的 `verify_relaxin_deb.py` 检查。

### 真机复测

1. 安装 2.0.4 FULL 包，确保 RELAXIN 白名单允许抖音；完全退出并重开抖音。
2. 推荐页连续浏览几条视频后分别长按，看是否无需先下滑即可打开自定义面板。再测试关闭和重开，检查是否出现原生面板闪现。
3. 开启底栏背景隐藏，切换视频和首页/消息，确认文字仍可点、背景透明。注意真正的视频画面是否覆盖底栏区域。
4. 观察进度条默认向下 10pt，文字默认 6pt；可手动填写 0 归位。检查底部 Home 指示条附近有无裁切。
5. 打开插件设置并进入二级页，测试一次返回，再在根页点击关闭或从左边缘向右滑，确认直接回到抖音，无中间白页。

**限制：** 本环境无 Theos / iOS SDK，静态审计通过并不能证明已成功编译、注入或完成真机行为验证。特别是抖音 40.8.0 的私有视图层级、原生长按手势优先级仍需设备验证。
