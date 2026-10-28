# 抖音助手 1.3 · 抖音 40.8.0 源码调整

本压缩包在原先的 1.2 源码上进行增量修改，保留了“解析下载地址”等功能。

## 1. 系统设置风格

- 新增 `DYYYSystemSettingsViewController.h/.m`：iOS 分组式设置列表、系统颜色/开关、SF Symbols 彩色分类图标。
- 设置主页和经 `DYYYSettingsHelper createSubSettingsViewController` 创建的子页面均使用新样式；保持原来的设置模型、标识符、点击回调、开关回调、冲突与依赖规则。
- 双指长按唤出的备用老设置界面尚保留；日常从抖音左侧入口打开的插件设置使用新版界面。

## 2. 底栏背景透明

- 修正 `DYYYHideBottomBg` 只清除部分背景层的问题，新增清理非按钮背景视图的处理。
- 开启“隐藏底栏背景”时，联动原来的全屏视频布局，避免底栏背景透明后仍显示黑色空白区域。
- 仍保留底栏功能按钮；某些子页面/皮肤效果可能需要根据真机视图结构继续适配。

## 3. 长按直接弹出双列模块化菜单

- 新增 `DYYYGridLongPressPanel.h/.m`，当抖音长按控制器出现时，直接覆盖显示可滚动的两列卡片菜单。
- 功能项使用原有 `AWELongPressPanelBaseViewModel.action` 回调，包括保存视频、解析下载地址等已开启项目。
- 对没有可直接调用 `action` 回调的抖音原生项目，点击切回“原生面板”；也有独立的“原生面板”按钮，确保原有交互仍可访问。
- 设置路径：“增强设置”→“交互增强”→“长按直接弹出双列面板”（默认为开启）。
- 特殊的原生菜单如果没有可识别按钮，会保留抖音原生表现。

## 修改的文件

- `DYYY.xm`
- `DYYYSettings.xm`
- `DYYYSettingsHelper.m`
- `DYYYLongPressPanel.xm`
- `DYYYSettingViewController.m`
- `DYYYSystemSettingsViewController.h/.m`（新增）
- `DYYYGridLongPressPanel.h/.m`（新增）
- `DYYYConstants.h`、`control`、`Makefile`

## 编译与测试

环境不提供 Theos / iOS SDK，**未编译 .deb，也未真机验证**。建议先备份数据，使用 Theos 编译，在抖音 40.8.0 的设备上重点验证：设置页前进/返回和切换开关、首页底栏透明与播放区布局、长按面板/原生操作回退、解析链接复制、横屏和特殊视频。
