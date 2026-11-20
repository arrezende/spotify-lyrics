import SwiftUI
import AppKit

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

struct LyricsRootView: View {
    @ObservedObject var model: PlayerModel
    let controller: PiPPanelController

    @State private var hovering = CommandLine.arguments.contains("--hover")

    private let radius: CGFloat = 13
    private let spotifyGreen = Color(red: 0.12, green: 0.84, blue: 0.38)
    private let controlsWidth: CGFloat = 118

    var body: some View {
        ZStack {
            if !model.transparentBackground {
                VisualEffectBlur(material: .hudWindow)
                Color.black.opacity(0.28)
            }

            if model.isCollapsed {
                collapsedBar
            } else {
                expandedContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(model.transparentBackground ? 0 : 0.12), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if !model.isCollapsed { controls }
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: model.transparentBackground)
        .animation(.easeInOut(duration: 0.22), value: model.currentIndex)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            lyricBlock
            Spacer(minLength: 4)
            transportRow
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(model.isPlaying ? spotifyGreen : Color.white.opacity(0.45))
                .frame(width: 10)

            Text(model.title.isEmpty ? "Spotify" : model.title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)

            if !model.artist.isEmpty {
                Text("·").foregroundStyle(Color.white.opacity(0.25))
                Text(model.artist)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)
            }

            if model.isDemo {
                Text("DEMO")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(spotifyGreen.opacity(0.25))
                    .foregroundStyle(spotifyGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }

            Spacer(minLength: 0)

            if abs(model.offset) > 0.001 {
                Text(String(format: "%+.1fs", model.offset))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(spotifyGreen.opacity(0.9))
            }
        }
        .padding(.trailing, hovering ? controlsWidth : 0)
        .shadow(color: .black.opacity(model.transparentBackground ? 0.55 : 0), radius: 3, y: 1)
    }

    private var lyricBlock: some View {
        Group {
            if model.hasLyrics {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.previousLine)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.44))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(model.transparentBackground ? 0.5 : 0), radius: 3, y: 1)

                    Text(model.currentLine)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(model.transparentBackground ? 0.6 : 0.35), radius: model.transparentBackground ? 5 : 3, y: 1)

                    Text(model.nextLine)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.44))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(model.transparentBackground ? 0.5 : 0), radius: 3, y: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.22), value: model.currentLine)
            } else {
                Text(model.statusText.isEmpty ? "…" : model.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(model.transparentBackground ? 0.5 : 0), radius: 3, y: 1)
            }
        }
    }

    /// Always reserves its height so showing it on hover does not shift the lyrics.
    private var transportRow: some View {
        HStack(spacing: 14) {
            transportButton("backward.fill", size: 10) { model.transport(.previous) }
            transportButton(model.isPlaying ? "pause.fill" : "play.fill", size: 12) { model.transport(.playPause) }
            transportButton("forward.fill", size: 10) { model.transport(.next) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 30, height: 20)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(model.transparentBackground ? 0.22 : 0.16))
                Capsule()
                    .fill(spotifyGreen)
                    .frame(width: max(0, geo.size.width * model.progress))
            }
        }
        .frame(height: 3)
    }

    // MARK: - Collapsed pill

    private var collapsedBar: some View {
        HStack(spacing: 7) {
            Image(systemName: model.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(model.isPlaying ? spotifyGreen : Color.white.opacity(0.45))

            Text(model.title.isEmpty ? "Spotify" : model.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
                .shadow(color: .black.opacity(model.transparentBackground ? 0.5 : 0), radius: 3, y: 1)

            if !model.artist.isEmpty {
                Text("·").foregroundStyle(Color.white.opacity(0.25))
                Text(model.artist)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if hovering {
                controlButton(model.isPlaying ? "pause.fill" : "play.fill") { model.transport(.playPause) }
                controlButton("chevron.up") { model.toggleCollapsed() }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Hover controls (PiP-style)

    private var controls: some View {
        HStack(spacing: 4) {
            controlButton("minus") { model.nudgeOffset(-0.25) }
            controlButton("plus") { model.nudgeOffset(0.25) }

            Spacer().frame(width: 2)

            controlButton(model.transparentBackground ? "circle.lefthalf.filled.inverse" : "circle.lefthalf.filled") {
                model.toggleTransparency()
            }
            controlButton("chevron.down") { model.toggleCollapsed() }
            controlButton("xmark") { controller.hide() }
        }
        .padding(7)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 17, height: 17)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
