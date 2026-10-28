# 影流助手 2.0.15（RELAXIN / RootHide）

本版重点：**原生视频直链解析与下载回退修复**，参见 [2.0.15 说明](README-2.0.15-原生视频解析和下载修复.md)。

从 2.0.13 保留：设置界面简化、评论区毛玻璃、长按边缘倍速、进度条与底栏调整、相册图集等功能。旧版详情见 [2.0.13 说明](README-2.0.13-设置文字精简与评论玻璃微调.md)。

构建目标：iPhone15,3、iOS 17.3、RELAXIN 0.4.8、RootHide、抖音 40.8.0。使用严格链接，不使用 `dynamic_lookup`；默认 `AWEMEVISION_STARTUP=full`，`LEGACY_LOADER_NAME=1`。

GitHub Actions 编译完成后须校验实际 DEB 包的架构、链接命令及注入过滤器。本环境尚未真机验证。
