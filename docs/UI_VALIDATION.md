# 界面与交互验证 · 0.3.1 · 2026-09-30

## 改动范围

SwiftUI 原生界面：Theme、MainView、DiscoverView、DetailSheet、SourcesView，以及播放器错误提示关闭按钮。保留 AppStore、MacTVBOXCore、网络协议、存储模型和播放解析逻辑。

命中区域在 label 完成 frame / padding 布局后设置 contentShape；覆盖透明 padding、Spacer 和完整选集格子。装饰描边不拦截事件。收藏 / 历史条目的主操作与移除按钮分离，没有嵌套按钮或行级手势劫持删除操作。

## 原生窗口实点验证

通过 CUA 读取实际窗口，再按截图坐标点击非文字区域，而不只是调用辅助功能按钮 action：

- 侧栏「我的收藏」文字右侧空白 → 切换到收藏页。
- 「热门电影」左侧 padding → 分类选中，横向推荐切换为影片网格。
- 第一张电影卡片底部右侧留白 → 打开该影片详情并匹配来源。
- 片源行中部空白 → 选中一碗并加载详情、线路和选集。
- HD中字选集右下角 padding → 打开播放器并显示该选集。
- 详情关闭按钮左上边缘 → 正常关闭 sheet。
- 最终包：历史记录行中部空白 → 打开对应视频，测试后关闭播放器。
- ⌘F → AX 焦点位于搜索输入框；设置片名并回车 → 显示聚合搜索结果。
- 主界面、分类网格、搜索结果、详情、历史列表均检查截图，未出现文字或按钮重叠。

历史中的播放测试会正常更新本机播放进度；未清空用户收藏、配置及历史。以上仅验证 UI 操作，不能据此保证所有第三方线路可播。

## 回归测试

本地 fixture-server 运行时执行：

```bash
MACTVBOX_CONFIG_FIXTURE="$PWD/build/research/feimao-config.txt" \
MACTVBOX_TEST_SERVER=http://127.0.0.1:18765 ./scripts/test.sh
```

**45 通过，0 失败，2 跳过。** 两项均为未启用的第三方在线可选测试（AppGet 媒体、豆瓣在线片单）。本轮 UI 内实际加载了线上片单，但不把它计入自动化测试通过数。日志在忽略的 build/ui-tests.log。

Release 编译、应用打包、ad-hoc 签名和 codesign 校验通过。版本为 0.3.1 / build 4；包为 build/MacTVBOX.app。构建仍有此前 CLT 的 Xcode 库搜索路径警告，不影响本机成功构建。

未对所有按钮逐一自动化遍历，也未验证所有 macOS 版本、屏幕缩放及 VoiceOver 完整导航。旧版功能和在线媒体验证见 VALIDATION.md。
