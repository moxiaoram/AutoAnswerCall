# 四个图标的截图提取资源

本目录图片提取自用户提供的《IMG_6487.jpeg》右侧按钮；处理后为透明背景 PNG，并非抖音官方原始 SVG/矢量资源，因此不能保证像素级完全一致。

程序运行时不从此文件夹加载图片：`DYYYCapturedFeedIcons.m` 已将四张 PNG 的精确字节嵌入 dylib，保证 RootHide 打包后也能找到资源。

命名：`like_before.png` 未点赞、`comment.png` 评论、`unfavorite.png` 未收藏、`share.png` 分享；选中态保留官方原图。
