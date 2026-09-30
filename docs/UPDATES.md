# 自动更新与 Release 发布

## 用户行为

0.6.0（build 9）开始集成 Sparkle 2.10.0。默认启动时检查更新，之后由 Sparkle 每小时调度；下载完成后在应用正常退出时安装，不强制重启、不打断播放。关闭窗口不一定等于退出应用；可使用 ⌘Q。菜单「MacTVBOX → 检查更新…」提供立即检查 / 安装界面，「自动更新」子菜单提供持久化开关与状态。

旧版 0.5.2 没有更新器，须先手动安装一次带更新器的版本。运行打包后的 `.app` 才能自更新，`swift run` 不支持。建议把应用移到 `/Applications` 或用户自己的 `~/Applications`，避免只读卷及受 macOS 文件夹隐私权限保护的位置。没有写权限时，Sparkle 可能要求系统授权；应用不绕过权限、不禁用 Gatekeeper。

## 信任链

- 固定订阅：`https://github.com/Vonfre/MacTVBOX/releases/latest/download/appcast.xml`。
- 包地址指向同一仓库的不可变版本标签，而不是可被覆盖的 `latest` ZIP。
- `SUPublicEDKey` 存在 Info.plist；更新包在解压前校验 Ed25519 签名。
- `SURequireSignedFeed=true` 同时验证订阅签名；签名失败不会过期后放行。
- 私钥仅在 macOS 钥匙串（service `https://sparkle-project.org`，account `app.mactvbox.desktop`）和 GitHub 仓库 Actions Secret `SPARKLE_PRIVATE_KEY` 中保存，不在 Git 或 Release 中发布。
- 发布脚本使用应用内公钥再次验证 ZIP，阻止误换 CI 私钥后发布无法安装的更新。
- Sparkle 二进制依赖固定为 2.10.0，SPM 自带下载 checksum；发布工具 tarball 也固定 SHA-256。
- 签名与下载失败由 Sparkle 处理；应用保持原版本，后续可重新检查；不自写 shell 替换正在运行的应用。
- GitHub 更新请求包含正常的客户端网络信息；不发送媒体库、片源凭据或历史，Sparkle 系统画像上传默认关闭。

Sparkle 的版权及第三方许可随应用保存在 `Contents/Resources/Sparkle-LICENSE.txt`。

## 本地构建

```bash
# 本机架构、ad-hoc 签名
./scripts/build-app.sh

# 双架构；输出到独立目录，不覆盖当前运行的开发版
APP_PATH="$PWD/build/release/MacTVBOX.app" ARCHS='arm64 x86_64' ./scripts/build-app.sh

# 构建 ZIP、签名 appcast.xml 和 SHA256SUMS；会访问钥匙串
./scripts/package-release.sh v0.6.0
```

如果通过受限临时文件提供已有私钥，设置 `SPARKLE_PRIVATE_KEY_FILE`；不要把私钥直接写进命令行、日志或工作区。临时文件使用权限 0600，操作完成即删除。不要随意重新生成 / 替换签名密钥，否则已安装客户端无法信任后续更新。请由仓库所有者妥善离线备份钥匙串私钥。

## 后续发布

1. 同时递增 `CFBundleShortVersionString`（如 0.6.1）和 `CFBundleVersion`（如 10；必须严格递增）。
2. 更新 README，并编写 `docs/releases/v0.6.1.md`。
3. 测试后提交代码，推送 main，创建并推送 `v0.6.1` 标签。
4. `.github/workflows/release.yml` 先测试，再构建通用应用；仅 tag 触发正式发布。
5. 工作流在草稿 Release 上传 ZIP、已签名 appcast 和校验文件，完成后一次性发布为 latest；不会修改已发布的 Release。若发布中途失败，可重跑并继续草稿。
6. 检查 Release 资产与签名、Actions 结果，并在旧版客户端验证更新。首次启用更新器的版本仍需手动安装。

`SPARKLE_PRIVATE_KEY` 已配置在仓库 Actions Secrets。PR 测试不接触签名私钥；只有 tag 的 release job 使用。不要向不可信分支或工作流暴露此 Secret。

## Apple 签名与公证

本轮环境没有 Developer ID 证书，因此发布的应用是 ad-hoc 签名，没有 Apple 公证。它与 Sparkle Ed25519 更新签名是不同层次的验证。完整商用发行仍需 Developer ID、hardened runtime、嵌套代码签名、公证与 stapling；仅设置 `CODE_SIGN_IDENTITY` 不能自动完成这些步骤。

## 自动化测试

```bash
python3 -m unittest discover -s scripts/testing -p 'test_*.py' -v
# 在已登录的 macOS 图形会话运行；生成全新测试密钥、bundle ID 和临时应用
python3 scripts/testing/test-updater-integration.py
```

安装测试编译生产 `UpdateController.swift`，走真实 Sparkle 下载、签名和安装器。四种情况：正常自动安装、篡改 ZIP、篡改 feed、拒绝降级。测试只操作随机命名的临时应用和偏好 / 缓存，不操作用户的 MacTVBOX 应用或媒体库。每次测试日志在忽略目录 `build/update-tests/`。测试应用放在系统临时目录，避免 Documents 文件夹授权弹窗干扰安装器。
