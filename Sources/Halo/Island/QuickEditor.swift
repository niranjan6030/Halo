import AppKit
import SwiftUI

/// A small floating window for typing — the island itself can't take keyboard focus.
/// Used for the quick note and for adding a reminder. It closes when you click away.
@MainActor
final class QuickEditor {
    static let shared = QuickEditor()

    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?

    func editNote(below anchor: CGRect) {
        show(title: "Quick Note", anchor: anchor, size: CGSize(width: 420, height: 300)) { close in
            NoteEditorView(close: close)
        }
    }

    func addReminder(below anchor: CGRect, add: @escaping (String) -> Bool) {
        show(title: "New Reminder", anchor: anchor, size: CGSize(width: 380, height: 112)) { close in
            ReminderEntryView(add: add, close: close)
        }
    }

    /// The field for Halo Intelligence. Submitting closes the field but leaves the
    /// island's own card open — that's where the answer streams in.
    func askHalo(below anchor: CGRect, submit: @escaping (String) -> Void) {
        show(title: "Ask Halo", anchor: anchor, size: CGSize(width: 420, height: 60), borderless: true) { close in
            AskHaloView(submit: { text in
                close()
                submit(text)
            }, cancel: close)
        }
    }

    private func show<Content: View>(title: String, anchor: CGRect, size: CGSize,
                                     borderless: Bool = false,
                                     @ViewBuilder content: (_ close: @escaping () -> Void) -> Content) {
        close()
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = frontmost }

        let panel: NSPanel = borderless ? BorderlessEditorPanel(contentRect: CGRect(origin: .zero, size: size))
                                        : EditorPanel(contentRect: CGRect(origin: .zero, size: size))
        panel.title = title
        let root = content { [weak self] in self?.close(returnFocus: true) }
        panel.contentView = NSHostingView(rootView: root.frame(width: size.width, height: size.height))
        panel.setFrameOrigin(CGPoint(x: (anchor.midX - size.width / 2).rounded(), y: (anchor.minY - size.height - 12).rounded()))
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close(returnFocus: Bool = false) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        if returnFocus { previousApp?.activate() }
    }
}

private struct AskHaloView: View {
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SiriColors.all[1])
            TextField("Ask Halo…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    submit(trimmed)
                }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AngularGradient(colors: SiriColors.all, center: .center), lineWidth: 1.3)
                .opacity(0.75)
        }
        .onAppear { focused = true }
    }
}

private final class BorderlessEditorPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isMovableByWindowBackground = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        QuickEditor.shared.close(returnFocus: true)
    }
}

private final class EditorPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        QuickEditor.shared.close(returnFocus: true)
    }
}

/// The note is kept in Island's preferences, so it's there after a restart.
enum QuickNote {
    static let key = "quickNote"
}

private struct NoteEditorView: View {
    let close: () -> Void
    @AppStorage(QuickNote.key) private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Quick Note", systemImage: "note.text")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            TextEditor(text: $note)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                .focused($focused)
            Text("Saved as you type · ⌘↩ or esc to close")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 30, leading: 16, bottom: 14, trailing: 16))
        .background(.regularMaterial)
        .onAppear { focused = true }
    }
}

private struct ReminderEntryView: View {
    let add: (String) -> Bool
    let close: () -> Void
    @State private var title = ""
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("New reminder", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(submit)
            Text(failed ? "Couldn't add it — check Reminders access in Privacy & Security." : "↩ to add · esc to close")
                .font(.system(size: 11))
                .foregroundStyle(failed ? Color.red : Color.secondary)
        }
        .padding(EdgeInsets(top: 34, leading: 16, bottom: 14, trailing: 16))
        .background(.regularMaterial)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if add(title) {
            close()
        } else {
            failed = true
        }
    }
}
