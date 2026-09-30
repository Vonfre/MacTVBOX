import SwiftUI
import UniformTypeIdentifiers
import MacTVBOXCore

struct SourcesView: View {
    @EnvironmentObject var store: AppStore
    @State private var showFile = false
    @State private var filter = ""
    @State private var onlySupported = false
    @State private var bridgeSource: Source?
    private var filteredSources: [Source] {
        store.sources.filter { (!onlySupported || $0.isSupported) && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.api.localizedCaseInsensitiveContains(filter)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                VStack(alignment: .leading, spacing: 9) {
                    Text("片源管理").font(.system(size: 28, weight: .semibold))
                    Text("无需在这里切换片源：先选择影片，应用会自动检索匹配来源。").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { store.showAddSource = true } label: { Label("添加接口", systemImage: "plus") }.buttonStyle(PrimaryButton())
            }
            VStack(alignment: .leading, spacing: 17) {
                HStack { Label("TVBox 配置订阅", systemImage: "link").font(.system(size: 14, weight: .semibold)); Spacer(); Badge(text: "支持 JSON / JSONC") }
                HStack(spacing: 10) {
                    TextField("http:// 或 https:// 配置地址", text: $store.configurationAddress).textFieldStyle(.plain).padding(12).background(Theme.background).clipShape(RoundedRectangle(cornerRadius: 8))
                        .onSubmit { Task { await store.importConfiguration() } }
                    Button { Task { await store.importConfiguration() } } label: {
                        if store.isImporting { ProgressView().controlSize(.small) } else { Label("导入 / 刷新", systemImage: "arrow.clockwise") }
                    }.buttonStyle(PrimaryButton()).disabled(store.isImporting)
                    Button("本地文件") { showFile = true }.buttonStyle(QuietButton())
                }
                Text("只读取配置，不执行 JAR、JavaScript、网页脚本或广告过滤规则。HTTP 配置采用明文传输，请确认来源可信。").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                if let configuration = store.configuration {
                    ForEach(Array(configuration.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(22).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "puzzlepiece.extension").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("运行时扩展").font(.system(size: 14, weight: .semibold))
                    Text("支持 TVBox type=4 HTTP 接口。对未适配的 Spider / JS 源，可连接你已部署的兼容服务。没有内置 Android / Node 运行时；连接成功也不代表上游资源一定可播放。")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(18).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 14) {
                statistic("\(store.sources.count)", "已导入片源", "square.stack.3d.up")
                statistic("\(store.supportedSources.count)", "已适配协议", "checkmark.shield")
                statistic("\(store.sources.count - store.supportedSources.count)", "需要额外适配", "puzzlepiece.extension")
            }
            HStack {
                Text("全部片源").font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle("仅显示已适配", isOn: $onlySupported).toggleStyle(.checkbox).font(.system(size: 11))
                TextField("筛选片源…", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            if filteredSources.isEmpty {
                ContentUnavailable(icon: "externaldrive", title: store.sources.isEmpty ? "尚未导入片源" : "没有匹配的片源", message: "支持 XML / JSON 及 csp_AppGet 原生协议；其他插件保留并注明所需运行时。")
            }
            LazyVStack(spacing: 9) {
                ForEach(filteredSources) { source in
                    HStack(spacing: 15) {
                        Image(systemName: source.isSupported ? "checkmark.circle" : "puzzlepiece.extension")
                            .font(.system(size: 20)).foregroundStyle(source.isSupported ? Theme.accent : Theme.muted)
                            .frame(width: 42, height: 42).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 9) { Text(source.name).font(.system(size: 13, weight: .semibold)); Badge(text: source.kindLabel, color: source.isSupported ? Theme.accent : Theme.muted) }
                            Text(source.compatibilityNote).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2).textSelection(.enabled)
                        }
                        Spacer()
                        if source.isSupported {
                            Badge(text: source.searchable ? "参与影片搜索" : "源未开放搜索")
                        } else { Text("未接入").font(.system(size: 11)).foregroundStyle(.orange.opacity(0.8)) }
                        if source.type == 3 {
                            Button(source.bridgeURL == nil ? "连接运行时" : "管理连接") { bridgeSource = source }.buttonStyle(QuietButton())
                        }
                        if store.customSources.contains(where: { $0.id == source.id }) {
                            Button { store.removeSource(source) } label: { Image(systemName: "trash").foregroundStyle(Theme.muted) }.buttonStyle(IconButton()).accessibilityLabel("移除此片源")
                        }
                    }.padding(15).background(Theme.panel.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .sheet(item: $bridgeSource) { source in RuntimeBridgeSheet(source: source).environmentObject(store) }
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.json, .plainText]) { result in
            switch result { case .success(let url): store.importFile(url); case .failure(let error): store.error = error.localizedDescription }
        }
    }
    private func statistic(_ count: String, _ title: String, _ icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) { Text(count).font(.system(size: 26, weight: .semibold, design: .rounded)); Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            Spacer()
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Theme.accent.opacity(0.6))
        }.padding(21).background(Theme.panel.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AddSourceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var type = 1
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("添加影视接口").font(.system(size: 23, weight: .bold))
            Text("使用你有权访问的标准影视采集 API，或已部署的 TVBox HTTP 服务，不是网站首页或插件文件。").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Form {
                TextField("片源名称", text: $name)
                TextField("接口地址", text: $address)
                Picker("接口格式", selection: $type) { Text("JSON · type=1").tag(1); Text("XML · type=0").tag(0); Text("TVBox HTTP · type=4").tag(4) }
            }.textFieldStyle(.roundedBorder)
            Text("例如：https://your-server.example/api.php/provide/vod/\nTVBox HTTP 请填写服务导出的单源 API；需要服务端已部署插件。").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(5)
            if let error { Text(error).font(.callout).foregroundStyle(.orange) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(QuietButton()); Button("添加并浏览") {
                do { try store.addSource(name: name, address: address, type: type); dismiss() } catch { self.error = error.localizedDescription }
            }.keyboardShortcut(.defaultAction).buttonStyle(PrimaryButton()) }
        }.padding(30).frame(width: 550).background(Theme.background).preferredColorScheme(.dark)
    }
}

struct DirectPlaySheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var playback: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 29)).foregroundStyle(Theme.accent)
            Text("把链接，变成一场放映。").font(.system(size: 23, weight: .bold))
            Text("输入 HLS（m3u8）或系统支持的 MP4 等媒体直链。\n网页地址、网盘口令和需要第三方解析的链接无法直接播放。").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(6)
            TextField("https://example.com/video.m3u8", text: $address).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.callout).foregroundStyle(.orange) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(QuietButton()); Button("开始播放") {
                do { let url = try URLTools.httpURL(address); playback.playDirect(url, store: store); playback.present(); dismiss() }
                catch { self.error = error.localizedDescription }
            }.keyboardShortcut(.defaultAction).buttonStyle(PrimaryButton()) }
        }.padding(32).frame(width: 570).background(Theme.background).preferredColorScheme(.dark)
    }
}
