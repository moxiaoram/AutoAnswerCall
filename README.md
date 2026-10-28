# 影流助手 2.0.6（RELAXIN / RootHide）

2.0.6 修复 Makefile 框架链接写法和 GitHub Actions 缺少 ldid；见 [构建修复说明](README-2.0.6-CI链接与ldid修复.md)。

此工程在 2.0.4 基础上修改底栏背景与评论区毛玻璃的运行时显示逻辑，并保留原有设置、Hook 初始化及 RootHide 严格链接策略。

详见 [2.0.6 底栏背景与评论区毛玻璃修复说明](README-2.0.6-底栏背景与评论区毛玻璃.md)。

> 源码静态校验通过不代表抖音私有视图兼容或真机注入通过。构建使用项目 `.github/workflows/build.yml` 中的 RELAXIN / RootHide 路径。
