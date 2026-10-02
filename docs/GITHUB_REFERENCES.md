# GitHub 架构参考记录 · 2026-09-30

以下按历史阶段记录阅读和架构参考，不代表集成完整项目。开发过程中曾在私有 Android 环境实测插件，现已改为原生协议并移除该环境；未将所读 GPL 实现复制进应用源码。

## 用户指定：FongMi/TV

- 仓库：https://github.com/FongMi/TV
- 本次读取默认分支 `fongmi`，GitHub 标记 GPL-3.0。
- 阅读 README、`app/src/main/java/com/fongmi/android/tv/model/VideoViewModel.java`、`ViewModelSearchRunner.java`、`app/src/main/java/com/fongmi/android/tv/playback/vod/VodDataSource.java`。
- 项目为 Android TV/手机应用；README 说明 CatVod Spider、Media3/ExoPlayer/mpv 与 Android 构建依赖，不是 macOS SDK。
- 可借鉴的结构：外部配置定义站点；站点搜索/详情/播放请求分层；搜索使用任务取消、超时及代次过滤；播放引擎与内容获取分离。

MacTVBOX 的对应实现：

| 思路 | 本项目 |
|---|---|
| 内容目录与播放地址分离 | `RankingClient` / `RankedTitle` 只负责公开片单；`SourceMatch` 才指向源记录 |
| 搜索任务控制 | AppStore 最多3源并发、旧任务取消、UUID代次防止旧结果覆盖 |
| 查详情与解析分离 | `TVClient.detail` → `TVClient.resolve` / `AppGetProvider` |
| 播放器独立 | `PlayerController` 在解析完成后创建 AVURLAsset，默认内置 AVPlayer |
| 来源匹配 | `TitleMatcher` 按片名/年份分组并标明不确定性，用户选择版本 |

没有移植 FongMi 的 Java/Android 播放引擎或完整 Spider 运行时。若后续复制/链接第三方 GPL 实现，需单独审查许可、源码提供与分发义务，而不能简单改名打包。

## 其他已阅读项目

- https://github.com/shareu007/tvbox-Swift-macOS — MIT。SwiftUI/CMS 与可选 CatVod Node 网关的结构可参考；Node 网关本身不使 Android Java/DEX JAR 自动兼容。
- https://github.com/yaolin-dev/OKVideoMac — GPL-3.0。SwiftUI/AppKit、mpv、QuickJS/Node 与可选 Android Dex bridge；重型运行时并未安装或集成。
- https://github.com/heroaku/TVboxo/blob/main/Py/app/getapp.py — 阅读公开 AppGet 通信协议后独立实现 Swift HTTP/AES 适配；未复制/分发其 Python 实现，未移植 OCR/验证码自动处理。

临时研究材料曾保存在被 Git 忽略的目录，现已清理；不是应用资源或发布物。

## 0.4.0 HTTP 运行时桥接参考

- https://github.com/Hululu007/drpy-node/blob/main/controllers/api.js — 读取 `/api/:module` 路由的公开调用协议：`wd` 搜索、`ac+t` 分类、`ac+ids` 详情、`play+flag` 播放，默认返回首页。研究快照控制器 blob 为 `6e878bd85fedba1b3bfc281627007c5cfac576b2`。
- MacTVBOX 独立实现 `HTTPSpiderProvider`，保留模块参数、不透明播放 ID 与原始线路标识；没有复制或捆绑该服务实现。
- 本版只增加进程外 HTTP 边界，没有安装上述项目的运行时，也没有执行用户配置的 Android / JS 插件。配置文件、服务端插件和客户端 HTTP 适配是三个不同层次；不能将其等同为全部源兼容。

使用方法及限制见 `RUNTIME_BRIDGE.md`。服务项目自身的部署安全、许可证及插件授权需要单独审查。


## 0.5.0 播放设置参考

读取 FongMi/TV 默认分支 `fongmi` 的以下文件作功能与架构参考：

- `app/src/main/java/com/fongmi/android/tv/bean/History.java`：按影片历史保存 opening / ending。
- `app/src/main/java/com/fongmi/android/tv/setting/PlayerSetting.java`：将播放引擎、显示缩放、背景播放等设置集中管理。
- `app/src/main/java/com/fongmi/android/tv/ui/dialog/TrackDialog.java`：根据播放器实际轨道提供选择，不虚构档位。
- `app/src/leanback/java/com/fongmi/android/tv/ui/activity/VodActivity.java`：Android 播放页面组织。

本版独立重写为 SwiftUI `PlayerPage`、`AVPlayerLayer` 和 `PlayerController`，使用 AVFoundation 实际 HLS variants 提供分辨率上限。没有复制或链接上述 Java 实现，也不声称与 Android 播放功能完全一致。

## 0.6.2 原生 Spider 协议

- 阅读 FongMi/CatVodSpider 的 `app/src/main/java/com/github/catvod/spider/Bili.java`，用于理解官方 HTTP API、分P、登录与 DASH 代理的边界。未复制/链接该 Java 实现；原生 Swift 实现只包含本轮验证的公开单文件 MP4 流程。
- 当前用户订阅的 JAR 容器经检查内含 `classes.dex`，不是普通 JVM class 集合。早期 Android 验证曾执行该容器，当前原生版不执行、不分发它。
- 动漫84适配依据站点实际 HTML / JSON / POST 通信实现，不加载广告脚本或移植第三方爬虫源码。
- 研究快照已清理。所有状态与验证边界见 `SPIDER_COMPATIBILITY.md`。

## 0.6.2 轻量原生迁移 · 2026-10-02

开发中曾独立实现 Android companion 验证插件，现按用户要求删除该实现、模拟器生命周期管理、APK资源和本机专用运行环境，不作为最终架构保留。

荐片和瓜子的协议依据用户订阅插件的静态协议分析及实际HTTP响应，重新实现为 Swift `JianpianProvider` / `GuaziProvider`。运行时仅依赖 Foundation、CommonCrypto、Security 和 AVFoundation；不加载下载的可执行代码。保留的协议常量用于兼容站点线协议，不是用户账号凭据。没有将反编译源码、JAR、JADX或Java运行时打进应用。

这不是FongMi播放引擎的移植，也不意味着所有CatVod插件可兼容。研究过程的独立实现说明不能替代正式分发前的授权、安全和许可审查。本地开发版未发布Release。当前覆盖与实测见 `SPIDER_COMPATIBILITY.md`、`V0_6_2_VALIDATION.md`。


## 本轮原生入口扩展（2026-10-02）

新增Jpys、AppRJ、AppQi及五种专项公开内容入口。实现依据订阅线协议静态分析和站点当前公开HTTP/HTML/JSON响应，未捆绑插件可执行代码或反编译源码。Jpys按响应的访客权限筛选清晰度，体育线路缺失权限字段时拒绝；没有绕过登录、验证码、付费或DRM。未声称FongMi的Android框架已移植；仍为本项目的Swift/AVFoundation实现。详见SPIDER_COMPATIBILITY.md及V0_6_2_VALIDATION.md。
