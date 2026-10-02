# MacTVBOX · 0.6.2

SwiftUI + AVKit 原生 macOS 点播客户端。**先找影片，再选来源**，不需要先切换片源。无需 Electron、无需安装 VLC 才能使用内置播放器。

## 0.6.2 轻量原生片源适配

- **移除 Android 环境**：不再下载模拟器、启动 AVD、安装 APK 或执行远程 JAR/DEX；不需要 JVM、Node 或后台桥接服务。
- **荐片、瓜子改为 Swift 原生协议**：直接完成首页、分类、搜索、详情、选集和媒体解析。瓜子的游客会话、请求签名与加密使用 macOS 系统库，会话只保存在内存。
- 两个源都用生产 `PlayerController` 完成实际视频帧解码、跳至 90 秒、暂停、下一集、上一集验证；测试时没有 Android 进程。不是只检查 HTTP 200 或播放地址。
- 瓜子按上游实际提供的清晰度生成线路；荐片只保留受支持的 HTTP 媒体，不把 FTP/P2P 当成可播放视频。
- 当前39条配置入口中，**23条原生协议入口**。在原15条基础上新增Jpys、AppRJ、AppQi、YGP、FirstAid、Kugou、Kanqiu、兔小贝；新增8条均有至少一个样本实际解码通过。剩余8条待原生适配、5条网盘、3条工具。**协议支持数不等于全库播放成功数。**
- Jpys另已通过生产播放器跳转90秒、暂停、上下集与恢复进度测试；登录限定清晰度不使用。AppQi搜索当前HTTP404，可从「片源管理 → 浏览内容」分类选片。
- 增加按源目录/分类/分页入口，但主发现流程仍然先选影片再查源；正片、预告片、音乐、体育、科普和儿童内容分开匹配。
- 旧 Android 临时映射自动忽略，收藏和观看进度保留；用户明确配置的外部 HTTP 服务仍保留。不把未移植的插件标记为可用。
- 保留应用内播放器、单行控制栏、方向键快进、全屏延时隐藏、片头片尾、自动下一集、批量历史管理。

详见 [Spider 接入清单](docs/SPIDER_COMPATIBILITY.md) 与 [0.6.2 验证](docs/V0_6_2_VALIDATION.md)。通用安装包与签名自动更新订阅由 GitHub Actions 发布，详见 [0.6.2 发布说明](docs/releases/v0.6.2.md)。

## 下载与自动更新（0.6.2）

[下载最新 Release](https://github.com/Vonfre/MacTVBOX/releases/latest) · [0.6.2 发布说明](docs/releases/v0.6.2.md)

- 下载 `MacTVBOX-0.6.2-universal.zip`，解压并将应用拖入「应用程序」。包含 Apple Silicon / Intel 两种架构，要求 macOS 13+；实际运行验证在 Apple Silicon 完成。
- **默认自动检查、下载，并在退出时自动安装**，不强制打断播放。启动时检查，运行期间每小时检查；菜单「MacTVBOX → 检查更新… / 自动更新」可以手动检查、查看状态或关闭自动更新。
- 更新订阅与 ZIP 均通过 Ed25519 签名验证；失败时保留旧应用，不触碰收藏、片源和播放历史。
- **0.5.2 及更早版本须手动安装一次 0.6.2**，之后才能自动接收后续 Release。
- 本版仍为 ad-hoc 签名，**尚未 Apple Developer ID 公证**；首次打开可能需要在 macOS「隐私与安全性」中允许。更新签名不等于 Apple 公证，不要关闭系统安全检查。

已安装0.6.0/0.6.1的用户可直接检查更新至0.6.2；收藏、片源及观看历史保留。0.6.1对侧栏版本显示的修复继续保留，版本文字读取应用Info.plist。

构建、更新安全设计和后续发布流程见 [自动更新说明](docs/UPDATES.md)。

## 0.5.2 键盘快进与应用图标

- **键盘进度控制**：`←` / `→` 每次快退 / 快进 5 秒，按住按 macOS 键盘重复节奏连续跳转；输入框、原生控件、设置面板和拖动进度时不抢占方向键。暂停时跳转仍保持暂停。
- **全新应用图标**：深石墨底色搭配薄荷绿电视 / 播放符号，已打包为多分辨率 `.icns`。
- **主窗口内播放 + 单行悬浮控制栏**：进度条独立在上，播放 / 暂停、上一集 / 下一集、时间、清晰度、倍速、选集、音量、设置、影院和全屏集中在下方一行。
- 设置与选集改为画面内浮层，不再常驻占据右侧空间，也不打开系统播放弹窗。`⌘←` / `⌘→` 保留前后 10 秒跳转。
- **一键全屏 / 双击画面全屏**；全屏时自动隐藏媒体库侧栏，播放中闲置约 3 秒，标题与底栏淡出。移动鼠标或按键重新显示；暂停、拖动进度、打开面板及鼠标停在控制区时不隐藏。
- `Esc` 优先关闭面板，再次按退出全屏。全屏仍是同一个应用窗口。
- 保留按影片片头片尾、自动下一集、实际 HLS 清晰度上限与加载 / 暂停状态保护。

使用说明见 [播放器说明](docs/PLAYER.md)，本版验证见 [0.5.2 验证](docs/V0_5_2_VALIDATION.md)，此前逻辑与 HLS 实测见 [0.5.0 验证](docs/V0_5_VALIDATION.md)。底层仍是 AVPlayer，并非完整移植 FongMi 的 Android 引擎。

## 已有功能（0.4.0）

- **运行时桥接**：支持 TVBox type=4 / drpy-node 风格 HTTP 单源接口；原有 Spider / JS 源可在「片源管理 → 外部服务」映射到受信任服务。仍然先选影片，再聚合搜索来源。
- **双推荐来源**：豆瓣电影、剧集、综艺、动漫；烂番茄流媒体电影、院线电影、热门剧集。分别展示评分 / 新鲜度，不混为一个排行。
- **卡片媒体库**：最近播放与收藏改为自适应卡片；最近播放显示上次集数、观看时间，选集区域独立滚动。
- **批量管理**：多选、全选、删除确认；删除正在播放的历史后，不会被定时进度保存立即加回，直到再次主动播放。
- 延续深灰 / 鼠尾草绿主题、整块点击热区、统一圆角及悬停反馈。

0.6.2 保留可选的手动 HTTP 服务连接，但内置片源直接在 Mac 运行，不依赖服务。Android 兼容环境已移除，未加入 JS / Node 规则执行器。详见 [HTTP 接口说明](docs/RUNTIME_BRIDGE.md)。

## 本版使用流程

1. 无需安装运行环境，直接打开「发现」，选择**豆瓣或烂番茄公开片单**。豆瓣包含热门电影、热播剧集、热门综艺、热门动漫；烂番茄包含流媒体热门电影、院线电影、热门剧集。每栏标注来源、获取时间，提供原网页链接。保留来源顺序，不宣称是全网实时播放量排行。
2. 点击影片，自动按片名搜索配置中已适配且开放搜索的片源，逐个显示命中结果。
3. 在影片详情选择来源 → 线路 → 剧集，使用内置 AVPlayer 播放。同一来源的其他记录放在「其他版本」菜单；近似片名、年份冲突另行折叠，需人工核对。
4. 顶部搜索栏可跨片源搜索。同名且年份一致的结果合并为影片卡片，标明来源数量。年份未知、不同季度/版本不会盲目合并。
5. 「片源管理」仅负责订阅与自定义接口管理，不是首页内容的切换开关。默认配置地址为用户提供的 `http://肥猫.net`。

**搜索命中 ≠ 播放通过**。失败、超时和验证码片源分别报告；每源仅搜索第一页，未检索不代表不存在该片。

## 兼容状态

2026-10-02 的用户配置快照有 **39个type=3入口，23个已适配原生协议**；剩余8个待适配、5个网盘、3个工具/元数据。兔小贝是精确配置的原生替代，不代表通用JS支持。数量随上游配置变化；协议适配不代表站点全部在线或所有视频都可播放。

- 支持苹果 CMS 风格 JSON / XML、TVBox JSON/JSONC 配置、`csp_AppGet`、`csp_Bili`、`csp_Dm84`、`csp_Jianpian`、`csp_Gz360`，本轮新增8个适配（详见接入清单），以及 TVBox HTTP type=4 / 单源运行时映射的分类、搜索、详情和播放解析。
- HTTP 运行时必须返回 `parse=0` 的媒体直链；网页嗅探 / 二次解析响应会明确报错，不会作为可播放媒体交给播放器。
- AppGet 采用独立 Swift HTTP/AES 实现，不下载或执行远程 JAR、DEX、JavaScript。验证码、登录、次数限制不会绕过。
- 已实测部分一碗、蔬菜媒体的原生视频帧解码，但也出现过 TLS 错误、403、额度提示视频和广告。**不能保证任一站点或全部线路持续可用**。
- 内置 AVPlayer 支持系统可解码的媒体，提供自定义控制栏、全屏、倍速、片头片尾、自动下一集、收藏与续播；新控制层暂未实现画中画与音轨 / 字幕切换。
- VLC 为用户自行安装的**可选外部播放器**，未内嵌 VLC 核心。未安装时入口禁用并提供官方下载页，不再制造播放失败错误。交给 VLC 不保证保留鉴权请求头。
- 没有实现网盘登录、网页嗅探、DRM、完整 CatVod/Android 运行时、IPTV/EPG。

豆瓣与烂番茄仅提供影片元数据，不提供本应用的播放资源。豆瓣采用公开网页所用的 JSON 片单端点；烂番茄读取公开分类网页的 JSON-LD 元数据，保留页面顺序及英文原名（均非承诺稳定的开发者 API）。服务变更、限流或验证时显示错误，用户仍可搜索。不会用片源广告列表静默替代推荐。烂番茄英文片名可能无法命中只收录中文名的片源，可手动搜索中文译名。

## 构建 / 运行

系统最低声明 macOS 13，当前仅在 Apple Silicon / macOS 26.6.2 实测。

```bash
./scripts/build-app.sh
open build/MacTVBOX.app
```

重新打包前退出已运行的应用。产物 `build/MacTVBOX.app` 使用当前机器架构和本地 ad-hoc 签名，尚未 Developer ID 公证。可拖入「应用程序」。

本机仅安装 Command Line Tools；`scripts/swift.sh` 使用已安装的 26.5 SDK 避开默认 27 SDK 的宏插件问题，不修改系统开发目录。完整 Xcode 可直接打开 `Package.swift`。建议运行 `.app`（包含兼容 HTTP 的 ATS 设置），而非直接运行裸 Swift 二进制。

播放界面空格播放 / 暂停，`⌘←` / `⌘→` 后退 / 前进 10 秒。

快捷键：`⌘L` 打开媒体地址，`⌘R` 刷新榜单/搜索，`⌘1/2/3` 切换发现/收藏/记录，`⌘,` 片源管理。

## 分层

```text
DiscoveryCatalog / RottenTomatoes      双来源公开片单与匹配规则（不含播放地址）
AppStore                               影片聚合、跨源检索、取消/请求代次、状态
TVClient / AppGetProvider / VODParser   原生片源浏览、搜索、详情与协议解析
JianpianProvider / GuaziProvider        原生荐片 / 瓜子协议、会话与清晰度线路
BiliSpiderProvider / Dm84SpiderProvider 原生 B站 / 动漫84 HTTP 协议
JpysSpiderProvider / LegacyAppSpiderProvider  Jpys / AppRJ / AppQi 原生协议
PublicWebSpiderProvider / KugouSpiderProvider 专项公开目录/视频/MV
SourceCatalogSheet                    可选按源目录、分类、搜索、分页
SourcePersistence                     旧临时桥接映射迁移，保留历史与外部服务
HTTPSpiderProvider                    type=4 / 外部运行时单源 HTTP 协议
LibraryView / LibrarySupport           卡片、批量管理、删除后的进度写入保护
PlayerController / PlayerPage         地址解析、播放状态机、自定义主窗口播放页
PlaybackPolicy                        续播、片头片尾与时间边界的可测试纯逻辑
LibrarySnapshot                        用户订阅、来源版本收藏、续播记录
```

参考 FongMi/TV 的检索任务、数据访问和播放分层，**并非其 macOS 移植**，未复制或捆绑其 GPL 实现。详见 `docs/GITHUB_REFERENCES.md`。

## 数据与网络

- 音量、自动下一集和按影片跳过设置位于应用 UserDefaults；
- 资料位于 `~/Library/Application Support/MacTVBOX/library.json`；旧版本丢弃 `ext` 的配置会重新获取，保留收藏与历史。
- 文件明文保存，包括来源 URL、AppGet 配置密钥/令牌、媒体 URL、本地文件路径、运行时映射及可能携带的接口凭据；不要公开分享。最近播放最多 100 条。
- 无应用账号、遥测或整份资料库上传。自动更新会访问 GitHub Release（可在菜单关闭，不上传媒体库）；会向豆瓣、烂番茄及封面服务器请求元数据，并将搜索词/片名发送给已适配片源。启用桥接后，影片 ID、线路和播放请求也会发给你配置的服务；不会自动上传原配置的 ext、Cookie 或 JAR。
- HTTP 明文仅为兼容性选择；系统 TLS 验证保持开启。所有接口响应有超时和体积限制，XML 禁止 DTD/实体，远程脚本不执行。
- 海报有内存缓存、体积限制和缩略采样；读取失败显示占位图。
- 无应用内置广告不代表第三方媒体无广告。请仅使用自己有权访问的内容。
- 当前未启用 App Sandbox；正式发行还需进一步审计、签名、公证与平台测试。

## 测试

```bash
python3 scripts/fixture-server.py
# 另一个终端：
MACTVBOX_TEST_SERVER=http://127.0.0.1:18765 ./scripts/test.sh
```

可选环境变量：

- `MACTVBOX_CONFIG_FIXTURE=/absolute/path/config.txt`：用户配置离线快照。
- `MACTVBOX_LIVE_RANKING=1`：豆瓣四类片单在线验证。
- `MACTVBOX_LIVE_RT=1`：烂番茄三类片单在线验证。
- `MACTVBOX_LIVE_APPGET=1`：实际来源浏览、搜索、详情、解析、HLS 请求；上游故障会如实失败。

无 XCTest 的 CLT 使用本仓库断言运行器执行相同测试体，不把跳过当作通过。播放器集成测试：`./scripts/test-player.sh`（合成本地视频 + 生产控制器，不读写真实用户媒体库）；`MACTVBOX_LIVE_HLS=1` 可额外验证 Apple 公开 HLS 档位。

本轮结果见 `docs/V0_6_2_VALIDATION.md`；早期结果见 `docs/V0_5_1_VALIDATION.md`；0.5.0 结果见 `docs/V0_5_VALIDATION.md`；0.4.0 结果见 `docs/V0_4_VALIDATION.md`；早期媒体验证和限制见 `docs/VALIDATION.md`、`docs/COMPATIBILITY.md`。旧研究快照和签名地址样本已清理；当前不含凭据的验证日志保存在被忽略的 `build/native-migration/` 和 `build/native-expansion/`。

原生荐片 / 瓜子在线完整播放测试（显式联网，使用隔离内存资料库，不改用户收藏/历史）：

```bash
MACTVBOX_LIVE_NATIVE=1 scripts/test-native-playback.sh jianpian
MACTVBOX_LIVE_NATIVE=1 scripts/test-native-playback.sh guazi
```

新增原生入口解码测试（显式联网、静音、无媒体文件落盘）：

```bash
MACTVBOX_LIVE_SPIDER=1 scripts/test-native-expansion-playback.sh
# Jpys / AppRJ / AppQi 使用含 sources 字段的 TVConfiguration 离线快照，非原始 sites 配置：
MACTVBOX_LIVE_SPIDER=1 MACTVBOX_NATIVE_CONFIG=/absolute/path/config.json scripts/test-native-expansion-playback.sh
MACTVBOX_LIVE_NATIVE=1 MACTVBOX_NATIVE_CONFIG=/absolute/path/config.json scripts/test-native-playback.sh jpys
```

可设 `MACTVBOX_SOURCE_FILTER=csp_AppQi` 仅检查一路。私密配置不随项目分发，不要上传凭据或签名媒体地址。失败会返回非零退出码，未设显式联网开关不会访问上游。
