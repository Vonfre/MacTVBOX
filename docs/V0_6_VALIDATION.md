# 0.6.0 发布验证

本地环境：Apple Silicon，macOS 26.6.2，Command Line Tools。SwiftPM 固定 Sparkle 2.10.0。

- 核心 + 本地 HTTP 协议：64 passed / 0 failed / 4 skipped。跳过项需要外部网络或用户提供的配置，未假定通过。
- 发布元数据与安全默认值：7 项通过，包括版本标签一致性、包名、大小、公钥、签名长度及必需签名校验配置。
- 生产 UpdateController + 真实 Sparkle 安装器：4 项通过。
  - 自动检查 → 下载 → 校验 → 正常退出 → bundle build 1 自动替换为 2；替换后 codesign 校验通过。
  - 原长度 ZIP 内容篡改：拒绝安装，旧 bundle build 1 不变。
  - 已签名 appcast 内容篡改：拒绝更新，旧 bundle build 1 不变。
  - 客户端 build 2、服务器 build 1：不降级。
- 生产播放器集成测试通过（本地合成视频）。
- 键盘 / 全屏控制栏集成测试通过。
- Release 主可执行文件包含 `x86_64 arm64`；`codesign --verify --deep --strict` 通过。
- ZIP Ed25519 签名使用应用内嵌公钥验证通过；订阅 XML 完成签名与签名验证。

测试应用采用随机 bundle ID、独立密钥和系统临时目录；未覆盖正在运行的开发版，也未修改用户媒体库。二进制包输出到 `build/release/`。

限制：未在 Intel 实机及 macOS 13 实机运行；没有 Developer ID 证书，因此没有 Apple 公证。GitHub Actions 与线上 Release 的最终状态以对应运行记录为准；本页不把构建完成等同于已发布。
