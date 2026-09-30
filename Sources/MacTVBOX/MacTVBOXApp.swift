import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacTVBOXCore

@main
struct MacTVBOXApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var playback = PlayerController()
    @StateObject private var updates = UpdateController()
    var body: some Scene {
        WindowGroup("MacTVBOX", id: "main") {
            MainView().environmentObject(store).environmentObject(playback)
                .preferredColorScheme(.dark).tint(Theme.accent)
                .task { updates.start() }
        }
        .defaultSize(width: 1220, height: 810)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                Menu("自动更新") {
                    Toggle("自动检查更新", isOn: Binding(
                        get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }))
                    Toggle("自动下载并在退出时安装", isOn: Binding(
                        get: { updates.automaticallyInstalls }, set: { updates.setAutomaticallyInstalls($0) }))
                    Divider()
                    Text(updates.status)
                }
                Divider()
            }
            CommandGroup(replacing: .newItem) {
                Button("打开网络视频…") { store.showDirect = true }.keyboardShortcut("l")
            }
            CommandMenu("媒体库") {
                Button("发现") { playback.leavePlayer(); store.section = .discover }.keyboardShortcut("1")
                Button("我的收藏") { playback.leavePlayer(); store.section = .favorites }.keyboardShortcut("2")
                Button("最近播放") { playback.leavePlayer(); store.section = .history }.keyboardShortcut("3")
                Button("片源管理") { playback.leavePlayer(); store.section = .sources }.keyboardShortcut(",")
                Divider()
                Button("刷新榜单 / 搜索") { store.submittedQuery.isEmpty ? store.browse() : store.search() }.keyboardShortcut("r")
                Button("暂停播放") { playback.pause() }
            }
            CommandMenu("播放") {
                Button("播放 / 暂停") { playback.present(); playback.togglePlayback() }.disabled(!playback.hasMedia)
                Button("后退 10 秒") { playback.skip(by: -10) }.keyboardShortcut(.leftArrow, modifiers: .command).disabled(!playback.canSeek)
                Button("前进 10 秒") { playback.skip(by: 10) }.keyboardShortcut(.rightArrow, modifiers: .command).disabled(!playback.canSeek)
                Divider()
                Button("上一集") { playback.previousEpisode() }.disabled(!playback.hasPrevious)
                Button("下一集") { playback.nextEpisode() }.disabled(!playback.hasNext)
                Button("返回播放器") { playback.present() }.disabled(!playback.hasMedia)
            }
        }
    }
}

struct MainView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var playback: PlayerController
    @State private var showLocalFile = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            if !playback.theaterMode && !(playback.isPresented && playback.isFullScreen) {
                sidebar.frame(width: 196)
                Rectangle().fill(Theme.border).frame(width: 1)
            }
            if playback.isPresented { PlayerPage() } else {
                VStack(spacing: 0) {
                    topbar
                    Rectangle().fill(Theme.border).frame(height: 1)
                    if let error = store.error { banner(error, error: true) }
                    if let info = store.info { banner(info, error: false) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            switch store.section {
                            case .discover: DiscoverView()
                            case .sources: SourcesView()
                            case .favorites: libraryView(history: false)
                            case .history: libraryView(history: true)
                            }
                        }.padding(32).frame(maxWidth: 1500, alignment: .leading).frame(maxWidth: .infinity)
                    }.id(store.section)
                    footer
                }
            }
        }
        .background(Theme.background).frame(minWidth: 1000, minHeight: 680)
        .sheet(isPresented: $store.showDirect) { DirectPlaySheet().environmentObject(store).environmentObject(playback) }
        .sheet(isPresented: $store.showAddSource) { AddSourceSheet().environmentObject(store) }
        .sheet(isPresented: Binding(get: { store.detailVideo != nil }, set: { if !$0 { store.closeDetail() } })) {
            DetailSheet().environmentObject(store).environmentObject(playback)
        }
        .fileImporter(isPresented: $showLocalFile, allowedContentTypes: [.movie, .video, .audiovisualContent]) { result in
            if case .success(let url) = result { playback.playDirect(url, store: store); playback.present() }
            else if case .failure(let error) = result { store.error = error.localizedDescription }
        }
        .task { store.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow, window.canBecomeMain { playback.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in playback.saveProgress() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.accent)
                Text("MacTVBOX").font(.system(size: 17, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 22).padding(.top, 44).padding(.bottom, 36)
            sidebarHeading("媒体库")
            ForEach([Section.discover, .favorites, .history]) { section in navButton(section) }
            if playback.hasMedia {
                sidebarAction("正在播放", icon: "play.circle.fill", selected: playback.isPresented) { playback.present() }
            }
            sidebarHeading("管理").padding(.top, 28)
            navButton(.sources)
            Spacer(minLength: 30)
            VStack(spacing: 6) {
                sidebarAction("打开网络视频", icon: "link") { store.showDirect = true }
                sidebarAction("打开本地文件", icon: "folder") { showLocalFile = true }
            }
            HStack {
                Text("仅在本机保存资料")
                Spacer()
                Text("0.5.2")
            }.font(.system(size: 9)).foregroundStyle(Theme.muted).padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 22)
        }.background(Theme.sidebar)
    }
    private func sidebarHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 24).padding(.bottom, 10)
    }
    private func sidebarAction(_ title: String, icon: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }.font(.system(size: 12)).foregroundStyle(selected ? Theme.accent : Theme.muted)
                .padding(.horizontal, 13).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(SurfaceButton(selected: selected, restingOpacity: 0)).padding(.horizontal, 12)
    }
    private func navButton(_ section: Section) -> some View {
        Button { playback.leavePlayer(); store.section = section } label: {
            HStack(spacing: 11) {
                Image(systemName: section.icon).frame(width: 18)
                Text(section.rawValue)
                Spacer(minLength: 0)
                if section == .favorites && !store.favorites.isEmpty { Text("\(store.favorites.count)").font(.system(size: 10)) }
                if section == .sources && !store.sources.isEmpty { Text("\(store.sources.count)").font(.system(size: 10)) }
            }.font(.system(size: 13, weight: section == store.section && !playback.isPresented ? .semibold : .regular))
                .foregroundStyle(section == store.section && !playback.isPresented ? Theme.accent : Theme.muted)
                .padding(.horizontal, 13).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(SurfaceButton(selected: section == store.section && !playback.isPresented, restingOpacity: 0))
            .accessibilityAddTraits(section == store.section && !playback.isPresented ? .isSelected : [])
            .padding(.horizontal, 12).padding(.bottom, 5)
    }
    private var topbar: some View {
        HStack(spacing: 14) {
            Text(store.section.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("搜索电影、剧集、综艺", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .onSubmit { store.section = .discover; store.search() }
                if !store.query.isEmpty {
                    Button { store.query = ""; store.submittedQuery = ""; store.browse() } label: {
                        Image(systemName: "xmark")
                    }.buttonStyle(IconButton(size: 26)).help("清空搜索").accessibilityLabel("清空搜索")
                } else {
                    Text("⌘ F").font(.system(size: 10)).foregroundStyle(Theme.muted).allowsHitTesting(false)
                }
            }.padding(.leading, 13).padding(.trailing, 7).frame(width: 330, height: 40)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(searchFocused ? Theme.accent.opacity(0.6) : Theme.border).allowsHitTesting(false))
                .contentShape(Rectangle()).onTapGesture { searchFocused = true }
            Button { store.showDirect = true } label: { Image(systemName: "plus") }
                .buttonStyle(IconButton(size: 40)).help("打开网络视频 ⌘L").accessibilityLabel("打开网络视频")
        }.padding(.horizontal, 32).frame(height: 72)
        .background {
            Button("聚焦搜索") { searchFocused = true }.keyboardShortcut("f").hidden().accessibilityHidden(true)
        }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(store.isLoading || store.isImporting ? .orange : Theme.accent).frame(width: 5, height: 5)
            Text(store.isLoading ? "正在读取内容…" : "本地媒体工作空间")
            Spacer()
            Text("\(store.supportedSources.count) 个已适配协议 / \(store.sources.count) 个已导入")
            Text("·").padding(.horizontal, 4)
            Text("仅播放你有权访问的内容")
        }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 30).frame(height: 34).background(Theme.sidebar)
    }
    private func banner(_ text: String, error: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(error ? .orange : Theme.accent)
            Text(text).font(.system(size: 12)).textSelection(.enabled)
            Spacer()
            Button { if error { store.error = nil } else { store.info = nil } } label: { Image(systemName: "xmark") }.buttonStyle(IconButton(size: 28)).accessibilityLabel("关闭提示")
        }.padding(13).background((error ? Color.orange : Theme.accent).opacity(0.08))
    }
    private func libraryView(history: Bool) -> some View {
        LibraryView(history: history).id(history)
    }
}
