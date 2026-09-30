# 0.5.0 验证记录

## 环境与产物

- Apple Silicon / macOS 26.6.2，Command Line Tools Swift 6.4、SDK 26.5。
- `./scripts/build-app.sh` Release 编译、打包、ad-hoc 签名及严格校验成功。
- `build/MacTVBOX.app`：**0.5.0 / build 6**，已启动实测。
- 未做 Developer ID 公证；未覆盖 Intel 或最低声明 macOS 13。

## 核心回归

本地 fixture-server 运行时：

```bash
MACTVBOX_TEST_SERVER=http://127.0.0.1:18765 \
MACTVBOX_CONFIG_FIXTURE="$PWD/build/research/feimao-config.txt" \
./scripts/test.sh
```

**65 通过，0 失败，3 跳过**。CLT 断言运行器执行同一批测试体；跳过的是本轮未启用的 AppGet、豆瓣、烂番茄在线测试，不计入通过。

新增播放策略覆盖：片头 / 续播位置、片尾结束判断、超过视频长度的跳过保护、未知时长、无效值规范化、跳转边界、时间显示。既有配置、协议、桥接、存储及历史删除保护保持回归。

日志：`build/player-tests.log`（忽略目录）。

## 真实控制器集成测试

```bash
./scripts/test-player.sh
# 可选：访问 Apple 公开 HLS 样例
MACTVBOX_LIVE_HLS=1 ./scripts/test-player.sh
```

编译生产 `PlayerController`，只将 AppStore 替换为内存测试桩；使用 12 秒本地合成 H.264 视频。测试不读取或修改真实用户媒体库。

**17 项本地检查 + 2 项公开 HLS 检查通过：**

- 准备阶段暂停后不会自动开播；页面内播放状态及前后集能力正确。
- 暂停时 seek、改变速度不恢复播放。
- 音量和静音控制真实 AVPlayer；提高音量解除静音。
- 手动下一集应用当前影片的片头设置。
- 关闭自动下一集时，片尾跳过点暂停；重播回到片头跳过点。
- 自动下一集沿用片头 / 片尾，且不调用显式播放入口重置历史删除保护。
- 最后一集停止，不循环。
- 加载时离开页面，不会后台偷偷开播；回到播放器保留暂停状态。
- 按影片跳过设置、音量可恢复；另一影片不继承偏移。
- 进度通过存储接口写入。
- Apple 公开 HLS 实际读取 **270p、360p、432p、540p、720p、1080p**；选择档位设置真实 `preferredMaximumResolution`，自动档清除限制。

样例：`https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8`

清晰度验证是分辨率上限 API 的生效检查，不等于已逐档验证渲染分辨率、码率或画面质量；AVPlayer 仍可根据带宽降档。

日志：`build/player-integration.log`（忽略目录）。

## 原生 GUI 实测

使用实际打包应用的辅助功能树及截图检查：

1. 打开本地测试服务器的合成视频，只有 MacTVBOX 主窗口，没有独立播放器弹窗；实际显示 640 × 360 视频帧。
2. 播放、暂停、结束后重新播放入口正常；暂停画面没有系统播放按钮 / 悬浮控制条覆盖。
3. 下方常驻进度、播放、前后跳转、速度和音量；单视频的上一集 / 下一集禁用。
4. 通过进度条辅助功能减量动作改变暂停进度，仍保持暂停。未将此宣称为鼠标拖动全过程实测；seek 状态逻辑另有集成测试。
5. 影院模式隐藏两侧面板并保留应用控制栏，仍在同一窗口。
6. 右侧播放设置布局可用；片头秒数直接输入 5，步进控件同步到 5；测试后重置为 0。
7. 普通单档 MP4 的清晰度选择禁用，显示实际尺寸；未安装 VLC 时外部入口禁用，不影响内置播放。
8. 播放页面侧栏「正在播放」正确选中，返回后「发现」重新选中；直链视频的影片详情按钮禁用。

测试退出后，仅删除本次创建的 `direct` 来源、`http://127.0.0.1:18765/media.mp4` 测试历史，保留全部 7 条原始用户历史。未删除用户收藏或更改用户片源。

## 边界与未验证项

- 底层仍是 AVPlayer；没有移植 ExoPlayer、mpv、VLC 引擎或完整 FongMi Android 运行时。
- 没有复制 FongMi Java 代码；只参考功能划分，独立实现 SwiftUI / AVFoundation。
- 清晰度仅针对媒体实际提供的多档 HLS，不伪造档位，也不强制锁定某个码率。
- 自定义画面暂未实现画中画、字幕 / 音轨选择、AirPlay 控制。
- 未单独 GUI 验证主窗口系统全屏、多显示器、所有窗口尺寸及辅助功能组合。
- 本轮不代表所有第三方源、验证码、鉴权、编码或网络问题已解决。既有真实片源验证范围见 `VALIDATION.md` 与 `V0_4_VALIDATION.md`。
