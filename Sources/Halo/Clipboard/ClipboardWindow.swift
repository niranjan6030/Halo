import AppKit
import HaloCore
import SwiftUI

/// A borderless panel for the clipboard. It takes keyboard focus while open (for
/// search and the arrow keys) and hands it back to the previous app when it closes.
final class ClipboardPanel: NSPanel {
    var onClose: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Clicking anywhere else dismisses it, like Spotlight.
        onClose?()
    }
}

@MainActor
final class ClipboardWindowController {
    private let panel = ClipboardPanel()
    private let history: ClipboardHistory
    private let report: (String, String) -> Void
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel.isVisible }

    init(history: ClipboardHistory, report: @escaping (String, String) -> Void) {
        self.history = history
        self.report = report
        panel.onClose = { [weak self] in self?.close() }
        // Switching to another app (⌘Tab, a click elsewhere) dismisses it, like Spotlight.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(returnFocus: false) }
        }
    }

    func toggle() {
        panel.isVisible ? close() : show()
    }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = frontmost }
        let view = ClipboardView(history: history,
                                 close: { [weak self] in self?.close() },
                                 paste: { [weak self] item in self?.paste(item) },
                                 copyOnly: { [weak self] item in self?.copyOnly(item) })
        panel.contentView = NSHostingView(rootView: view)

        // Drops from just below the notch, so it reads as part of the island.
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.maxY - size.height - 48))
        }
        panel.alphaValue = 0
        // Keys only reach the active app, so Island has to be active while this is open.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        dismiss(returnFocus: true)
    }

    private func dismiss(returnFocus: Bool) {
        guard panel.isVisible else { return }
        panel.onClose = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.onClose = { [weak self] in self?.close() }
        // Give the keyboard back to whatever you were using, unless you clicked away
        // into another app (which is already in front).
        if returnFocus, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            previousApp?.activate()
        }
    }

    /// Copies the item and pastes it into the app you were using.
    private func paste(_ item: ClipboardItem) {
        history.copy(item)
        dismiss(returnFocus: false)
        guard AXIsProcessTrusted() else {
            previousApp?.activate()
            report("Copied — press ⌘V to paste", "doc.on.clipboard")
            return
        }
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyV: CGKeyCode = 9
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func copyOnly(_ item: ClipboardItem) {
        history.copy(item)
        close()
        report("Copied", "doc.on.clipboard")
    }
}

// MARK: - The window's content

struct ClipboardView: View {
    @ObservedObject var history: ClipboardHistory
    let close: () -> Void
    let paste: (ClipboardItem) -> Void
    let copyOnly: (ClipboardItem) -> Void

    @State private var query = ""
    @State private var kind: ClipboardItem.Kind = .all
    @State private var selection: ClipboardItem.ID?
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardItem] {
        history.items.filter { item in
            (kind == .all || item.kind == kind)
                && (query.isEmpty || item.searchText.localizedCaseInsensitiveContains(query)
                    || (item.sourceName ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    private var selected: ClipboardItem? {
        filtered.first { $0.id == selection } ?? filtered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if filtered.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: 330)
                    Divider().opacity(0.4)
                    if let selected {
                        ClipboardPreview(item: selected, paste: { paste(selected) }, copy: { copyOnly(selected) },
                                         pin: { history.togglePin(selected) }, delete: { delete(selected) })
                    }
                }
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 780, height: 500)
        .background { background }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .onAppear {
            searchFocused = true
            selection = filtered.first?.id
        }
        .onChange(of: query) { _, _ in selection = filtered.first?.id }
        .onChange(of: kind) { _, _ in selection = filtered.first?.id }
    }

    @ViewBuilder
    private var background: some View {
        if IslandSettings.shared.liquidGlass, #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(Color.black.opacity(0.35)),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            VisualEffect()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search clipboard", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.return) {
                        if let selected { paste(selected) }
                        return .handled
                    }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onKeyPress(keys: ["c", "p", "\u{7F}"], phases: .down) { press in
                        guard let selected else { return .ignored }
                        if press.key == KeyEquivalent("c"), press.modifiers.contains(.command) {
                            copyOnly(selected); return .handled
                        }
                        if press.key == KeyEquivalent("p"), press.modifiers.contains(.command) {
                            history.togglePin(selected); return .handled
                        }
                        if press.key == KeyEquivalent("\u{7F}"), press.modifiers.contains(.command) {
                            delete(selected); return .handled
                        }
                        return .ignored
                    }
                Text("\(history.items.count) items")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(ClipboardItem.Kind.allCases) { option in
                    Button {
                        kind = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11)
                            .frame(height: 24)
                            .background(Capsule().fill(kind == option ? Color.accentColor : Color.primary.opacity(0.08)))
                            .foregroundStyle(kind == option ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if history.items.contains(where: { !$0.isPinned }) {
                    Button("Clear") { history.clearUnpinned() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .help("Removes everything except pinned items")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(item: item, index: index, isSelected: item.id == selected?.id)
                            .id(item.id)
                            .onDrag { ClipboardDrag.provider(for: item) }
                            .onTapGesture(count: 2) { paste(item) }
                            .onTapGesture { selection = item.id }
                            .contextMenu {
                                Button("Paste") { paste(item) }
                                Button("Copy") { copyOnly(item) }
                                Button(item.isPinned ? "Unpin" : "Pin") { history.togglePin(item) }
                                Divider()
                                Button("Delete") { delete(item) }
                            }
                    }
                }
                .padding(8)
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: history.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(history.items.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.system(size: 15, weight: .semibold))
            Text(history.items.isEmpty ? "What you copy, screenshots you take and files you drop on the notch show up here."
                                       : "Try a different search or filter.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑↓", "Select")
            hint("⏎", "Paste")
            hint("⌘C", "Copy")
            hint("⌘P", "Pin")
            hint("⌘⌫", "Delete")
            hint("esc", "Close")
            hint("drag", "Into any app")
            Spacer()
            Text("Open anytime with ⌃⌘V")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .frame(height: 17)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
            Text(label)
                .font(.system(size: 11.5))
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Actions

    private func move(_ step: Int) {
        let items = filtered
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selected?.id } ?? 0
        selection = items[max(0, min(items.count - 1, current + step))].id
    }

    private func delete(_ item: ClipboardItem) {
        let items = filtered
        let index = items.firstIndex { $0.id == item.id } ?? 0
        history.remove(item)
        let remaining = filtered
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

/// What gets handed to another app when an item is dragged out.
enum ClipboardDrag {
    static func provider(for item: ClipboardItem) -> NSItemProvider {
        switch item.content {
        case let .image(_, file): return NSItemProvider(contentsOf: file) ?? NSItemProvider()
        case let .files(urls): return NSItemProvider(contentsOf: urls[0]) ?? NSItemProvider()
        case let .link(url): return NSItemProvider(object: url as NSURL)
        case let .text(text): return NSItemProvider(object: text as NSString)
        case let .color(color): return NSItemProvider(object: color.hexString as NSString)
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ClipboardThumbnail(item: item, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                HStack(spacing: 4) {
                    if let icon = appIcon(for: item.sourceBundleID) {
                        Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                    }
                    Text([item.sourceName, item.copied.formatted(.relative(presentation: .named))]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 0)
            if case let .text(text) = item.content, let action = SmartClipboardAction.detect(in: text) {
                Image(systemName: action.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .help(action.title)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white : Color.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }
}

struct ClipboardThumbnail: View {
    let item: ClipboardItem
    let size: CGFloat

    var body: some View {
        ZStack {
            switch item.content {
            case let .image(image, _):
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            case let .files(urls):
                Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable().padding(3)
            case .link:
                symbol("link", .blue)
            case let .color(color):
                Color(nsColor: color)
            case .text:
                symbol("text.alignleft", .gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private func symbol(_ name: String, _ tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(tint.opacity(0.18))
            Image(systemName: name)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

struct ClipboardPreview: View {
    let item: ClipboardItem
    let paste: () -> Void
    let copy: () -> Void
    let pin: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                switch item.content {
                case let .text(text):
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView {
                            Text(text)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let action = SmartClipboardAction.detect(in: text) {
                            SmartClipboardButton(action: action)
                        }
                    }
                case let .image(image, _):
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .link(url):
                    VStack(alignment: .leading, spacing: 10) {
                        ClipboardThumbnail(item: item, size: 56)
                        Text(url.absoluteString)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                        Button("Open in Browser") { NSWorkspace.shared.open(url) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case let .files(urls):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(urls, id: \.self) { url in
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                                        Text(url.deletingLastPathComponent().path)
                                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case let .color(color):
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: color))
                            .frame(height: 160)
                        Text(color.hexString).font(.system(size: 20, weight: .semibold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Text(item.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 8) {
                Button(action: paste) { Label("Paste", systemImage: "arrow.down.doc") }
                    .keyboardShortcut(.defaultAction)
                Button(action: copy) { Label("Copy", systemImage: "doc.on.doc") }
                Button(action: pin) { Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") }
                Spacer()
                Button(role: .destructive, action: delete) { Label("Delete", systemImage: "trash") }
            }
            .controlSize(.regular)
        }
        .padding(16)
    }
}

/// The frosted background, when Liquid Glass is off or unavailable.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
