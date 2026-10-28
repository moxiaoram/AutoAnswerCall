# 影流助手 2.0.15 — 首页长按面板 / 原画解析

- 首页直接长按立即生成可用插件动作：保存视频、封面、音频、图集、复制链接和文案、复制播放地址。官方动作必须等抖音返回其真实操作模型，不能伪造。
- TikHub 官方文档列出的 **原始上传最高画质** 接口：`GET https://api.tikhub.io/api/v1/douyin/app/v3/fetch_video_high_quality_play_url`。
  - 需要自行申请 Bearer Token，使用的是按次收费的第三方服务，**绝不后台自动调用**，只有点击原画动作后才请求。
  - API 返回 `data.original_video_url` 后可以复制或尝试下载。URL 可能有时效；不保证私密、区域限制视频可下载。
  - 默认没有 Token，也没有隐含提供共享密钥；使用前到插件设置填写 Token（保存在本机钥匙串（不会写入普通 UserDefaults 备份）），敏感环境建议勿保存长期 Token。
  - 文档：https://docs.tikhub.io/312096107e0 。文档核对不等于真机可用性验证。当前离线环境无法真实访问 API，**不能声称已实测能下载原画**。
- 开源的 https://github.com/zvrr/dt_download_API 文档提供 `GET /api?url=...` 的解析格式，公开演示服务质量不保证，故未作为强制默认接口。可自行搭建后把 URL 前缀配置到原有「接口解析保存媒体」中。
- RootHide / RELAXIN / iOS 17.3 / 抖音 40.8.0，保留严格链接且禁止 dynamic_lookup。
- 底栏背景透明仍依赖抖音当前真实播放器容器和视图层级。本版保留旧版保护，不承诺底栏已真机完全透明；需抓取真机布局日志才可继续精确修复。

## 离线验证

`python3 scripts/check_215_panel_original.py`

此检查只验证接线/源码条件，无法取代 macOS CI 编译和真机调用。仅用于对自己有权保存的公开视频执行下载。

## 底栏仍不透明时

开启「隐藏设置 → 底栏透明诊断」，连续打开两条推荐视频；通过 Filza 等设备文件管理器读取抖音容器 `Documents/AwemeVision-Footer-Diagnostic.txt`。该文件只记录 UIKit 视图类名、布局位置和背景不透明状态，不含视频地址或鉴权信息。关闭诊断后停止写入。这样才能判断到底是黑色底图还是视频播放层没有覆盖底栏。
