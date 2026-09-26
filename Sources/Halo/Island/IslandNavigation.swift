import HaloCore
import SwiftUI

/// The row of small icons along the bottom of an expanded island: jump between Music,
/// Controls, Weather and Calendar, or open the clipboard. A two-finger swipe across the
/// island moves between the same pages.
struct IslandNavigation: View {
    @ObservedObject var model: IslandModel
    let current: ExpandedContent
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.pages, id: \.self) { page in
                icon(symbol(for: page), label: label(for: page), selected: page == current) {
                    model.showPage(page)
                }
            }
            if model.settings.clipboardHistory {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 3)
                icon("doc.on.clipboard", label: "Clipboard  ⌃⌘V", selected: false) {
                    model.collapse()
                    model.openClipboard()
                }
            }
        }
        .padding(3)
        .glassCapsule()
        .frame(height: IslandModel.navigationHeight)
    }

    /// Narrower icons when many pages are on, so the row always fits the island.
    private var iconWidth: CGFloat {
        let count = model.pages.count + (model.settings.clipboardHistory ? 1 : 0)
        return count > 8 ? 27 : 32
    }

    private func icon(_ symbol: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                .frame(width: iconWidth, height: 22)
                .background {
                    // One highlight that glides from icon to icon.
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .matchedGeometryEffect(id: "selection", in: selection)
                    } else {
                        Capsule().fill(Color.white.opacity(0.001))
                    }
                }
                .symbolEffect(.bounce, value: selected)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(label)
        .accessibilityLabel(label)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }

    private func symbol(for page: ExpandedContent) -> String {
        switch page {
        case .nowPlaying: return "music.note"
        case .controls: return "square.grid.2x2.fill"
        case .weather: return "cloud.sun.fill"
        case .calendar: return "calendar"
        case .lyrics: return IslandPage.lyrics.symbol
        case .shortcuts: return IslandPage.shortcuts.symbol
        case .timer: return IslandPage.timer.symbol
        case .system: return IslandPage.system.symbol
        case .devices: return IslandPage.devices.symbol
        case .reminders: return IslandPage.reminders.symbol
        case .notes: return IslandPage.notes.symbol
        case .mirror: return IslandPage.mirror.symbol
        case .smartDrop: return "wand.and.stars"
        default: return "circle"
        }
    }

    private func label(for page: ExpandedContent) -> String {
        switch page {
        case .nowPlaying: return "Now Playing"
        case .controls: return "Controls"
        case .weather: return "Weather"
        case .calendar: return "Up Next"
        case .lyrics: return "Lyrics"
        case .shortcuts: return "Shortcuts"
        case .timer: return "Timer"
        case .system: return "System"
        case .devices: return "Devices"
        case .reminders: return "Reminders"
        case .notes: return "Quick Note"
        case .mirror: return "Mirror"
        default: return ""
        }
    }
}
