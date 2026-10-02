# 0.6.2 原生轻量版验证 · 2026-10-02

本文件替代早期0.6.2 Android实验验证说明。以下原生适配与GUI实测针对本地arm64应用，版本0.6.2 / build11。发布通用包由GitHub Actions另外执行核心测试、双架构构建及更新签名校验；Intel运行和真实旧版升级安装不能仅凭构建成功视为已实测。发布信息见 `releases/v0.6.2.md`。

## 当前交付范围（本轮扩展后的结果）

- 39条配置入口中：**23原生 / 8待适配 / 5网盘 / 3工具**。不是39条全部可播放，也不是23个独立站点的全库健康保证。
- 原有15条基础上，新增Jpys、AppRJ、AppQi、FirstAid、YGP、兔小贝、Kugou、Kanqiu共8条；无需Android、JVM、Node或本地服务。
- 真实请求调用生产TVClient；新增8条均至少一个样本通过AVFoundation有效像素帧解码，不以HTTP200、目录可见或有URL算播放成功。
- 主发现页仍先选影片再查来源；专项内容按角色分组，避免预告片/MV冒充正片。新增「片源管理 → 浏览内容」提供按源目录、分类、搜索和分页，不改变全局片源。

### 新增8条的在线解码

| 入口 | 实际解码分辨率 | 结果与限制 |
|---|---|---|
| Jpys | 864×648 | 首页/分类/搜索/25集详情；只用明确允许访客的档位，排除登录限定高清 |
| AppRJ | 1080×606 | 搜索结果第二个样本的备用线路通过；存在失效媒体/解析器 |
| AppQi | 1920×1080 | 最终测试首页30、分类30；搜索HTTP404；首个候选第三线路解码通过 |
| FirstAid | 1280×720 | 首页159条、分类19条；公开急救科普视频 |
| YGP | 1920×1080 | 首条无预告，第二个样本通过；只提供预告片，不是正片 |
| 兔小贝 | 1024×600 | 原JS配置精确替换为原生公开目录，59条样本目录 |
| Kugou | 404×270 | 公开MV样本通过；不能当作高清或付费音频已解锁 |
| Kanqiu | 1920×1080 | 第一场多条线路失败，第二场公开备用线路通过；未锁定权限字段必须明确存在 |

每次解码要求至少8帧且播放时间推进超过2秒，30秒超时；有限影片/线路尝试，静音且不保存媒体文件。不同测试样本的分辨率不同，不是清晰度保证。

最终日志在忽略目录 `build/native-expansion/`：`expanded-playback.log`、`jpys-playback.log`、`rj-live.log`、`qi-final.log`。失败尝试也保留，不只统计成功请求。

### Jpys生产播放器验证

`jpys-player.log`：搜索《西游记》→25集详情→解码8帧→跳至90秒并解码→暂停保持→下一集解码→上一集恢复约92秒并解码，全部通过。使用实际PlayerController、隔离内存AppStore，不写真实用户资料库。荐片/瓜子的同类验证见下方前轮记录。

### 最终自动化回归

- 核心 **118 passed / 0 failed / 6 skipped**，本机CLT断言运行器执行相同测试体，并非本机原生XCTest运行。6项跳过是需额外启用的5种在线测试和未提供的私密配置fixture，不计通过。
- 本轮新增19项测试：8类适配注册/精确JS替换、内容角色隔离、HTML/JSON解析、权限缺失拒绝、媒体/请求头校验、CRLF注入、RJ签名/multipart、Qi AES/form/404/空首页回退、Jpys独立签名向量/访客权限/剧集排序、MV与付费音频分离。
- 生产播放器合成媒体回归 **21项通过**；控制栏/全屏隐藏/方向键与焦点回归 **26项通过**。
- Release arm64构建、ad-hoc签名和 `codesign --verify --deep --strict` 通过。包中没有APK/JAR/DEX；动态链接仅系统库及既有Sparkle，没有新增第三方运行时。
- 已修正目录搜索失败后仍显示旧分页的问题；未匹配到测试来源时，在线脚本返回非零，避免零测试假成功。
- 未实测Intel/旧macOS；声明最低macOS13，实际Apple Silicon/macOS26.6.2。构建仍有既有工具链搜索路径/弃用提示，未关闭TLS验证。

### GUI验证

- 重新打开打包应用，侧栏23已适配/39已导入；管理页23原生、8待适配、5网盘、3工具。没有Android下载/启用面板。
- AppQi首页不再空白；实际点击电影分类、第二页加载成功。输入《西游记》显示HTTP404，点「返回目录」可恢复；四列海报卡片布局经截图检查。
- 目录选片后的跨源流程中观察到应用内瓜子版本播放器；该画面不计作AppQi播放通过，AppQi真实通过依据隔离解码脚本。GUI操作可能正常更新对应影片的最近播放；未删除任何收藏/历史。

### 本轮剩余边界

8个未移植：AppDrama×2、Hxq、Wwys、SaoHuo、Czsapp、SP360、GuaziTY。调查分别遇服务端密钥/配置错误、DNS失败、无效页面、HTTP522、浏览器验证、平台网页二次解析或无法验证的协议。另5个网盘入口未实现授权，3个工具不是点播源。详细逐项原因见 `SPIDER_COMPATIBILITY.md`。不绕过验证码、登录、付费或DRM；不把不能播放的入口换标签充数。

### 复现新增验证

```bash
MACTVBOX_LIVE_SPIDER=1 scripts/test-native-expansion-playback.sh
# 默认只测5种无需配置的专项入口；另外3种需要TVConfiguration格式快照（sources字段，不是sites）：
MACTVBOX_LIVE_SPIDER=1 MACTVBOX_NATIVE_CONFIG=/absolute/path/config.json scripts/test-native-expansion-playback.sh
MACTVBOX_LIVE_SPIDER=1 MACTVBOX_SOURCE_FILTER=csp_AppQi MACTVBOX_NATIVE_CONFIG=/absolute/path/config.json scripts/test-native-expansion-playback.sh
MACTVBOX_LIVE_NATIVE=1 MACTVBOX_NATIVE_CONFIG=/absolute/path/config.json scripts/test-native-playback.sh jpys
```

本轮私密配置、JAR/DEX、JADX/反编译源码、临时JS/原始响应及签名媒体URL研究快照已清理。保留永久适配/测试脚本、当前应用、无凭据日志；用户资料库、个人SDK和签名凭据不受影响。

---

## 前轮迁移记录（历史结果，以下15源统计不是当前覆盖）

### 前轮实现与范围

- 荐片和瓜子使用独立Swift协议适配；不执行Android/DEX/JAR，不需要JVM、Node或本机桥接服务。
- 从应用代码、构建与资源中删除Android生命周期管理、兼容面板、APK、构建/测试脚本与companion源码。
- 旧本机临时映射在读取资料时忽略；收藏、来源信息、历史进度与用户外部HTTP绑定保留。合成测试覆盖旧映射、非本机服务、元数据与时间保留。
- 本次39源快照为15原生入口（AppGet6、Bili6、Dm84、Jianpian、Gz360），15待原生适配、5网盘、1JS、3工具。入口数不是全部影片可播放保证。

## 无Android情况下的真实播放

先退出旧应用并停止其专用AVD，确认没有qemu/emulator进程，再执行生产 `PlayerController` 测试。使用独立内存AppStore、静音，不写真实用户资料库。每个解码检查至少取得8帧有效像素缓冲，不以HTTP200或非空URL作播放通过。

| 项目 | 荐片 | 瓜子 |
|---|---|---|
| 首页 / 分类 | 通过，10 / 42条 | 通过，107 / 30条 |
| 搜索 / 详情 | 西游记，25集样本 | 西游记，51集样本 |
| 实际解码 | 1920×1080 | 1450×1080 |
| 跳至90秒后解码 | 通过 | 通过 |
| 暂停保持 | 通过 | 通过 |
| 下一集并解码 | 1920×1080 | 1440×1080 |
| 上一集 / 恢复进度并解码 | 通过 | 通过 |

最终日志：`build/native-migration/jianpian-final.log`、`guazi-final.log`。节目是不同版本的同名测试样本，不能混为同一剪辑；上游视频可含水印或推广，并非本应用添加，也不承诺全库无广告或正版授权。

复现（显式联网，会随上游状态变化）：

```bash
MACTVBOX_LIVE_NATIVE=1 scripts/test-native-playback.sh jianpian
MACTVBOX_LIVE_NATIVE=1 scripts/test-native-playback.sh guazi
```

## 自动化回归

- 核心：**100 passed / 0 failed / 5 skipped**（本机CLT断言运行器，执行相同测试体）。使用本地fixture服务器和清理前的用户配置离线快照。
- 跳过的是需单独显式启用的在线AppGet、豆瓣、Bili、Dm84、烂番茄测试；不计作通过。荐片和瓜子的在线解码由上述独立生产播放器脚本验证。
- 原生新增测试包含请求/响应协议、表单编码、加密往返、真实TVClient合成传输、畸形响应拒绝、剧集清晰度、冲突ID、会话隔离与刷新，以及旧资料迁移。
- 生产播放器合成媒体测试：**21项通过**。
- 控制栏/全屏隐藏/方向键与焦点保护测试：**26项通过**。
- `scripts/build-app.sh` release arm64构建、`codesign --verify --deep --strict`通过；应用内没有APK/JAR/DEX。动态依赖为系统框架和Sparkle，不包含Android/JVM/Node。
- `git diff --check`通过。构建中存在工具链搜索路径和既有Swift捕获提示，不影响本次构建；没有关闭TLS证书验证。

复现核心测试：

```bash
python3 scripts/fixture-server.py --port 18765
# 另一终端；已清理含私密配置的离线快照，因此不设CONFIG_FIXTURE时该项会跳过。
MACTVBOX_TEST_SERVER=http://127.0.0.1:18765 scripts/test.sh
scripts/test-player.sh
scripts/test-player-chrome.sh
```

## 最终应用GUI验证

- 打开重新打包的应用，发现页正常显示；侧栏显示0.6.2、15已适配/39导入。
- 片源管理显示macOS原生说明、15原生/15待适配等分类，没有Android启用/下载/停止面板。
- 历史卡片与其他影片保留；旧荐片《西游记》第02集从约02:06续播到02:12，应用内显示真实画面，暂停有效。
- 旧瓜子《西游记》02 [1080P]从约00:23续播到00:33，应用内真实画面、暂停有效。没有外部播放器或桥接弹窗。
- 删除专用Android环境及缓存后，再次退出并冷启动最终应用，发现页正常显示，无模拟器进程。
- GUI操作会正常更新这两条测试历史的进度；未批量删除任何用户记录。

## 清理结果

删除对象清理前的磁盘分配占用合计 **5,121,556,480字节（约4.77 GiB）**；这是删除文件/缓存的占用统计，不是APFS全盘可用空间差值。

删除：
- `~/Library/Application Support/MacTVBOX/AndroidRuntime`：仅应用专用运行环境、镜像、AVD和下载插件。
- 工作区 `tools/AndroidSpiderBridge`，`build/android-runtime`、`android-bridge`、`android-playback-tests`。
- 旧 `build/published` / `release` 本地安装包、过期构建日志与测试二进制、重复 `build/sparkle`。
- `build/research` / `spider-research`：下载插件、反编译工具/源码、私密接口响应及签名媒体URL。
- 执行 `swift package clean` 清除过期Swift构建产物，依赖checkout/artifact仍保留以便后续构建。

保留：
- 当前 `build/MacTVBOX.app`（约9.4MiB磁盘占用）、源代码、合成测试与当前验证日志。
- `build/sparkle-tools` 发布工具、Sparkle公钥/更新订阅、Keychain签名凭据。
- `~/Library/Application Support/MacTVBOX/library.json`、收藏、观看历史、个人Android SDK与 `Medium_Phone_API_36.1` AVD。
- Git历史、tag、远端Release；没有发布、提交或推送。

详细一次性清理清单位于忽略目录 `build/native-migration/cleanup.json`。原生运行不依赖被删除的文件。

### 前轮结束时的边界（已被上方扩展结果更新）

前轮完成的是**去Android架构和荐片/瓜子原生迁移**，并非把30多个未知插件全部移植。剩余15条插件、网盘授权、JS、验证码、DRM及通用网页二次解析未实现。前轮B站/Dm84已验证样本解码，但本轮没有重新验证其全部在线接口；风控、DNS、签名变化与站点故障仍会导致播放失败。macOS13是声明下限，本轮实际平台为Apple Silicon/macOS26.6.2；未实测Intel/旧系统。
