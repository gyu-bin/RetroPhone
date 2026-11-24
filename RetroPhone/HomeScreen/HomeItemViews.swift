import SwiftUI

/// Classic icon + label (white Helvetica with heavy shadow).
struct AppIconCell: View {
    var app: AppID
    var metrics: HomeMetrics
    var editing: Bool
    var showLabel: Bool = true
    var pressed: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        let store = LayoutStore.shared
        VStack(spacing: 4) {
            RetroIconView(art: store.art(for: app), size: metrics.iconSize, customImage: store.customIcon(for: app))
                .brightness(pressed ? -0.35 : 0)
                .overlay(alignment: .topLeading) {
                    if editing, let onDelete { DeleteBadge(action: onDelete).offset(x: -9, y: -9) }
                }
            if showLabel {
                IconLabel(text: store.name(for: app), size: metrics.labelSize, width: metrics.cellWidth - 4)
            }
        }
        .wiggle(editing, seed: app.raw)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.name(for: app))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("icon.\(app.raw)")
    }
}

struct IconLabel: View {
    @Environment(\.retroTheme) private var theme
    var text: String
    var size: CGFloat
    var width: CGFloat
    var body: some View {
        Text(text)
            .font(theme.isFlat ? .neue(size) : .retroFixed(size, .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(theme.isFlat ? 0.3 : 0.95), radius: theme.isFlat ? 1 : 1.2, x: 0, y: theme.isFlat ? 0.5 : 1)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width)
    }
}

/// iOS 4 delete badge: black circle, white border and ✕.
struct DeleteBadge: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0x4A4A4A), Color(hex: 0x000000)], startPoint: .top, endPoint: .bottom))
                Circle().stroke(Color.white, lineWidth: 2)
                Image(systemName: "xmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("삭제"))
    }
}

/// Folder icon: dark glass tile with a 3×3 grid of miniature icons.
struct FolderIconCell: View {
    var folder: Folder
    var metrics: HomeMetrics
    var editing: Bool
    var highlighted: Bool = false
    var showLabel: Bool = true
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            FolderTile(apps: folder.apps, size: metrics.iconSize, highlighted: highlighted, cover: folder.cover)
                .overlay(alignment: .topLeading) {
                    if editing, let onDelete { DeleteBadge(action: onDelete).offset(x: -9, y: -9) }
                }
            if showLabel {
                IconLabel(text: folder.name, size: metrics.labelSize, width: metrics.cellWidth - 4)
            }
        }
        .wiggle(editing, seed: folder.name + "\(folder.apps.count)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LF("%@ 폴더, 앱 %d개", folder.name, folder.apps.count))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("folder.\(folder.name)")
    }
}

struct FolderTile: View {
    @Environment(\.retroTheme) private var theme
    var apps: [AppID]
    var size: CGFloat
    var highlighted: Bool = false
    var cover: String? = nil

    var body: some View {
        let store = LayoutStore.shared
        let mini = size * 0.22
        let shape = RoundedRectangle(cornerRadius: RetroIconView.cornerRadius(size), style: .continuous)
        ZStack {
            if theme.isFlat {
                // iOS 7: frosted light tile.
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .light)
                shape.fill(Color.white.opacity(0.22))
            } else {
                shape.fill(LinearGradient(colors: [Color.black.opacity(0.28), Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(LinearGradient(colors: [.black.opacity(0.6), .white.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            }
            if apps.isEmpty, let cover, let img = FileStore.loadImage(cover) {
                // The real folder tile from the screenshot (its mini icons), under the classic glass.
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size * 0.9, height: size * 0.9)
                    .clipShape(RoundedRectangle(cornerRadius: RetroIconView.cornerRadius(size * 0.9), style: .continuous))
                    .opacity(0.95)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: size * 0.06), count: 3), spacing: size * 0.06) {
                    ForEach(Array(apps.prefix(9).enumerated()), id: \.offset) { _, app in
                        RetroIconView(art: store.art(for: app), size: mini, customImage: store.customIcon(for: app), gloss: true)
                    }
                }
                .frame(width: size * 0.84, height: size * 0.84, alignment: .topLeading)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(highlighted ? 1.18 : 1)
        .animation(.easeOut(duration: 0.18), value: highlighted)
    }
}

/// Wiggle (jiggle) animation. Driven by TimelineView so it stops instantly when editing ends.
private struct WiggleModifier: ViewModifier {
    var active: Bool
    var seed: String
    var amplitude: Double = 1.8
    func body(content: Content) -> some View {
        if active {
            let phase = Double(seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 100) / 100 * .pi * 2
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                content
                    .rotationEffect(.degrees(sin(t * 2 * .pi * 3.4 + phase) * amplitude))
                    .offset(y: sin(t * 2 * .pi * 3.4 + phase + 1.3) * 0.6)
            }
        } else {
            content
        }
    }
}

extension View {
    func wiggle(_ active: Bool, seed: String, amplitude: Double = 1.8) -> some View {
        modifier(WiggleModifier(active: active, seed: seed, amplitude: amplitude))
    }
}

/// Glass dock with highlight and soft reflection band (iOS 7: a flat frosted band).
struct DockShelf: View {
    @Environment(\.retroTheme) private var theme
    var body: some View {
        if theme.isFlat {
            Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .light)
                .overlay(Color.white.opacity(0.15))
        } else {
            classic
        }
    }

    private var classic: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: .white.opacity(0.42), location: 0),
                .init(color: .white.opacity(0.22), location: 0.08),
                .init(color: .white.opacity(0.12), location: 0.5),
                .init(color: .white.opacity(0.06), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.75)).frame(height: 1)
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1).offset(y: 1)
        }
        .background(.ultraThinMaterial.opacity(0.35))
    }
}

/// Mirror reflection of a dock icon onto the glass shelf.
struct DockReflection: View {
    var app: AppID
    var size: CGFloat
    var body: some View {
        let store = LayoutStore.shared
        RetroIconView(art: store.art(for: app), size: size, customImage: store.customIcon(for: app))
            .scaleEffect(x: 1, y: -1)
            .mask(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
