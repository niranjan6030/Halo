import AppKit
import SwiftUI

// MARK: Lyrics

/// The line being sung, with the one before and after, following the song.
struct LyricsPageView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var lyrics: LyricsMonitor

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: model.notchSize.height - 4)

            if let track = nowPlaying.track {
                HStack(spacing: 10) {
                    ArtworkView(image: nowPlaying.artwork, size: 28, cornerRadius: 7)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(nowPlaying.accent.opacity(0.8))
                }
                .appearing(delay: 0.02)

                content(for: track)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appearing(delay: 0.08)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .onAppear(perform: load)
        .onChange(of: nowPlaying.track?.title) { _, _ in load() }
    }

    private func load() {
        guard let track = nowPlaying.track else { return }
        lyrics.load(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
    }

    @ViewBuilder
    private func content(for track: Track) -> some View {
        switch lyrics.state {
        case .idle, .loading:
            ProgressView().controlSize(.small).tint(.white)
        case let .synced(lines):
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let index = LyricsMonitor.index(in: lines, at: track.position(at: context.date))
                VStack(spacing: 6) {
                    line(index.flatMap { $0 > 0 ? lines[$0 - 1].text : nil }, size: 12.5, opacity: 0.35)
                    line(index.map { lines[$0].text }.flatMap { $0.isEmpty ? nil : $0 } ?? "♪", size: 18, opacity: 1, weight: .bold)
                    line(lines[safe: (index ?? -1) + 1]?.text, size: 12.5, opacity: 0.5)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
            }
        case let .plain(text):
            ScrollView {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        case .instrumental:
            message("Instrumental", symbol: "music.note")
        case .notFound:
            message("No lyrics for this song", symbol: "text.badge.xmark")
        case .failed:
            VStack(spacing: 8) {
                message("Couldn't reach the lyrics library", symbol: "wifi.exclamationmark")
                IslandPill(title: "Try Again", systemImage: "arrow.clockwise") {
                    lyrics.retry()
                    load()
                }
            }
        }
    }

    private func line(_ text: String?, size: CGFloat, opacity: Double, weight: Font.Weight = .semibold) -> some View {
        Text(text?.isEmpty == false ? text! : " ")
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white.opacity(opacity))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .id(text)
            .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
    }
}

// MARK: Shortcuts

struct ShortcutsPageView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var library: ShortcutsLibrary

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: model.notchSize.height - 2)
            if library.isLoaded && library.names.isEmpty {
                VStack(spacing: 10) {
                    Text("You don't have any shortcuts yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    IslandPill(title: "Open Shortcuts", systemImage: "square.stack.3d.up.fill", action: openApp)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(library.names, id: \.self) { name in
                            Button {
                                library.run(name) { worked in
                                    model.collapse()
                                    if worked {
                                        model.show(.success(text: name))
                                    } else {
                                        model.show(.message(text: "\(name) didn't finish", symbol: "exclamationmark.triangle.fill"))
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if library.running == name {
                                        ProgressView().controlSize(.mini).tint(.white)
                                    } else {
                                        Image(systemName: "square.stack.3d.up.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    Text(name)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .contentShape(Capsule())
                                .glassCapsule(interactive: true, tint: Color.white.opacity(0.1))
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(library.running != nil)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 118)
                .appearing(delay: 0.04)

                HStack {
                    Spacer()
                    IslandPill(title: "Open Shortcuts", systemImage: "arrow.up.forward.app", height: 26, action: openApp)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .onAppear { library.refresh() }
    }

    private func openApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
        model.collapse()
    }
}
