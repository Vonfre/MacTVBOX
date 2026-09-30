import SwiftUI
import MacTVBOXCore

struct RuntimeBridgeSheet: View {
    let source: Source
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var trusted = false
    @State private var testing = false
    @State private var status: String?
    @State private var testTask: Task<Void, Never>?
    @State private var revision = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 26)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("连接运行时").font(.system(size: 23, weight: .semibold))
                    Text(source.name + " · " + source.api).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Text("把这个源映射到你已部署的 TVBox HTTP / drpy-node 单源接口。应用仍按影片搜索，不需要来回切换片源。")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                Label("JS 规则 → 兼容该规则的 Node / JS 服务", systemImage: "curlybraces")
                Label("Android Spider → 兼容 Android 的执行服务", systemImage: "server.rack")
                Text("此功能不附带运行时，也不会把 Android JAR 自动转换为 JS。网盘授权、验证码、网页嗅探须由受信任服务合法处理；不能保证所有源可播放。")
                    .foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 12)).padding(16).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            TextField("http://127.0.0.1:5757/api/你的规则", text: $endpoint).textFieldStyle(.roundedBorder)
                .onChange(of: endpoint) { _ in testTask?.cancel(); revision = UUID(); testing = false; status = nil; trusted = false }
            Text("填写服务导出的单源 API，不是订阅地址、JS 文件或 JAR 地址。源的 ext、Cookie、JAR 不会自动上传；服务端须自行配置对应插件。")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Toggle("我信任此服务，允许将片名、影片 ID 和播放请求发送给它", isOn: $trusted).font(.system(size: 12))
            if let status { Text(status).font(.system(size: 12)).foregroundStyle(Theme.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(testing ? "正在检测…" : "检测接口") { test() }.buttonStyle(QuietButton()).disabled(!trusted || testing || !valid)
                if source.bridgeURL != nil {
                    Button("断开映射") { do { try store.setBridge(nil, for: source); dismiss() } catch { status = error.localizedDescription } }.buttonStyle(QuietButton())
                }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("保存连接") {
                    do { try store.setBridge(endpoint, for: source); dismiss() } catch { status = error.localizedDescription }
                }.buttonStyle(PrimaryButton()).disabled(!trusted || !valid || testing)
            }
        }.padding(30).frame(width: 650).background(Theme.background).preferredColorScheme(.dark)
            .onAppear { endpoint = source.bridgeURL ?? "" }
            .onDisappear { testTask?.cancel(); revision = UUID() }
    }
    private var valid: Bool { (try? URLTools.httpURL(endpoint)) != nil }
    private func test() {
        testing = true; status = nil
        var candidate = source; candidate.bridgeURL = endpoint
        let current = UUID(); revision = current
        testTask = Task {
            do {
                let page = try await TVClient().browse(source: candidate)
                guard !Task.isCancelled, revision == current else { return }
                status = "接口响应有效：\(page.categories.count) 个分类、\(page.videos.count) 条内容。仅验证首页协议，尚未验证搜索、插件执行和实际播放。"
            } catch {
                guard !Task.isCancelled, revision == current else { return }
                status = "检测失败：" + store.friendlyError(error)
            }
            testing = false
        }
    }
}
