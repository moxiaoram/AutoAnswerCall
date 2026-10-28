# 影流助手 2.0.10：底栏与评论文字白底专项修复

目标环境：iPhone15,3 / iOS 17.3 / RELAXIN 0.4.8 / RootHide / 抖音 40.8.0。

## 问题和源码原因

1. 2.0.9 在稳定 Feed 模式中，`DYYYFullScreenOrClearTabBar()` 返回 NO，两个 `AWEDPlayer*ViewController` 因而跳过视频内容区域延伸。现在只在底栏空缺高度符合预期时扩展 `contentView`，不修改 Feed 列表、Cell 高度或滚动位置。底栏透明仍依赖抖音实际渲染内容。
2. 评论区递归背景清理跳过了所有 `UILabel` 和 `UIControl`，因此昵称、时间、回复、展开等文字上的白色矩形保留。现在仅在评论区毛玻璃开启时，清理浅白色文字背景/图层，和 attributedText 中的浅白背景属性；关闭时恢复，复用时重新检测。不会清理头像图片或全局 UILabel。

## 重要边界

这些修正针对已经找到的源码逻辑漏洞，并不保证所有播放器类型、所有富文本组件在 40.8.0 都能覆盖。若底栏仍有黑区，需要针对真机视频渲染容器检查。

## 构建

使用项目内 GitHub Actions RootHide 工作流，默认 FULL、legacy_loader_name=true、probe_only=false。保持严格链接，不得添加 `-Wl,-undefined,dynamic_lookup`。本环境无法实际运行 iOS SDK/Theos 编译及真机验证。
