import SwiftUI
import ImageIO
import MacTVBOXCore

enum Theme {
    static let background = Color(red: 0.055, green: 0.061, blue: 0.069)
    static let sidebar = Color(red: 0.073, green: 0.080, blue: 0.088)
    static let panel = Color(red: 0.100, green: 0.110, blue: 0.120)
    static let accent = Color(red: 0.65, green: 0.85, blue: 0.75)
    static let muted = Color(red: 0.60, green: 0.64, blue: 0.67)
    static let border = Color.white.opacity(0.075)
}

// Put the hit shape AFTER layout: transparent padding and spacers are interactive too.
private struct InteractiveSurface: View {
    var configuration: ButtonStyleConfiguration
    var selected = false
    var restingOpacity = 0.035
    var radius: CGFloat = 10
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var body: some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(hovering && isEnabled ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                .allowsHitTesting(false))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
    private var fill: Color {
        if configuration.isPressed && isEnabled { return Color.white.opacity(0.14) }
        if selected { return Theme.accent.opacity(0.12) }
        return Color.white.opacity(hovering && isEnabled ? 0.075 : restingOpacity)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PaddedButton(configuration: configuration, prominent: true)
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PaddedButton(configuration: configuration)
    }
}
private struct PaddedButton: View {
    var configuration: ButtonStyleConfiguration
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    var body: some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16).frame(minHeight: 38)
            .foregroundStyle(prominent ? Theme.background : Color.white.opacity(0.88))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(RoundedRectangle(cornerRadius: 10).fill(prominent
                ? Theme.accent.opacity(configuration.isPressed ? 0.7 : 1)
                : Color.white.opacity(configuration.isPressed ? 0.13 : hovering ? 0.09 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(hovering ? Theme.accent.opacity(0.35) : Theme.border).allowsHitTesting(false))
            .opacity(enabled ? 1 : 0.4).onHover { hovering = $0 }
    }
}
struct SurfaceButton: ButtonStyle {
    var selected = false
    var restingOpacity = 0.035
    func makeBody(configuration: Configuration) -> some View {
        InteractiveSurface(configuration: configuration, selected: selected, restingOpacity: restingOpacity)
    }
}
struct IconButton: ButtonStyle {
    var size: CGFloat = 36
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size)
    }
}
private struct IconButtonBody: View {
    var configuration: ButtonStyleConfiguration
    var size: CGFloat
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    var body: some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .frame(width: size, height: size).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(configuration.isPressed ? 0.14 : hovering ? 0.10 : 0.045)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(hovering && enabled ? Theme.accent.opacity(0.35) : Color.clear).allowsHitTesting(false))
            .opacity(enabled ? 1 : 0.4).onHover { hovering = $0 }
    }
}

struct Badge: View {
    var text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.10)).clipShape(Capsule())
    }
}

struct ContentUnavailable: View {
    var icon: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(Theme.accent)
                .frame(width: 76, height: 76).background(Theme.accent.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 22))
            Text(title).font(.system(size: 19, weight: .semibold))
            Text(message).font(.system(size: 13)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 470)
        }.frame(maxWidth: .infinity).padding(.vertical, 34)
    }
}

@MainActor private enum PosterCache {
    static let images: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>(); cache.totalCostLimit = 32 * 1024 * 1024; return cache
    }()
    static let client = TVClient()
}

struct Poster: View {
    var video: Video
    @State private var loadedImage: NSImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.14, green: 0.22, blue: 0.23), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "film").font(.system(size: 33, weight: .ultraLight)).foregroundStyle(Theme.accent.opacity(0.3))
            if let image = loadedImage { Image(nsImage: image).resizable().scaledToFill() }
        }.clipped()
        .task(id: video.poster) {
            loadedImage = nil
            guard let url = try? URLTools.httpURL(video.poster) else { return }
            if let cached = PosterCache.images.object(forKey: url as NSURL) { loadedImage = cached; return }
            var request = URLRequest(url: url)
            if let host = url.host, host == "doubanio.com" || host.hasSuffix(".doubanio.com") {
                if video.id.hasPrefix("douban:") { request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer") }
                else if video.id.hasPrefix("rt:") { request.setValue("https://www.rottentomatoes.com/", forHTTPHeaderField: "Referer") }
            }
            guard let (data, _) = try? await PosterCache.client.fetch(request, limit: 6 * 1024 * 1024), !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return }
            let image = NSImage(cgImage: thumbnail, size: .zero)
            PosterCache.images.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            loadedImage = image
        }
    }
}

struct VideoCard: View {
    var video: Video
    var subtitle: String? = nil
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    Poster(video: video).frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if !video.remarks.isEmpty {
                                Text(video.remarks).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6)).padding(10)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if hovering {
                                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30).background(.ultraThinMaterial, in: Circle()).padding(10)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.aspectRatio(2.0 / 3.0, contentMode: .fit)
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        .frame(height: 36, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading)
                    Text(subtitle ?? (video.metadata.isEmpty ? "查看影片" : video.metadata))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                }.padding(10)
            }.padding(4).contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(SurfaceButton()).onHover { hovering = $0 }
        .accessibilityLabel(video.title + "，" + video.remarks)
        .accessibilityHint("查看影片详情和匹配片源")
    }
}
