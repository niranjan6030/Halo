import AppKit

/// The three-dot menu on the Now Playing card.
///
/// It is a real AppKit menu, so it looks and behaves like the one in Music itself.
/// Every item does something, and anything that can fail says so in the island
/// rather than failing silently.
@MainActor
final class MusicMenu: NSObject, NSMenuDelegate {
    private weak var model: IslandModel?
    private var playlistsItem: NSMenuItem?
    /// Kept alive while the menu is on screen.
    private static var presented: MusicMenu?

    /// `autoDismissAfter` is used when the menu is opened for a check rather than by
    /// a click, so it can never be left hanging on screen.
    static func present(model: IslandModel, at location: NSPoint? = nil, autoDismissAfter: TimeInterval? = nil) {
        guard let track = model.nowPlaying.track else { return }
        let menu = MusicMenu()
        menu.model = model
        presented = menu
        model.setMenuOpen(true)
        let built = menu.build(for: track, model: model)
        if let autoDismissAfter {
            // Scheduled before popUp, which runs its own event loop until dismissed.
            let timer = Timer(timeInterval: autoDismissAfter, repeats: false) { _ in built.cancelTracking() }
            RunLoop.main.add(timer, forMode: .common)
        }
        built.popUp(positioning: nil, at: location ?? NSEvent.mouseLocation, in: nil)
    }

    private func build(for track: Track, model: IslandModel) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        if MusicActions.isAppleMusic(track.bundleID) {
            let favourited = MusicActions.isFavourited() ?? false
            add(to: menu, title: favourited ? "Remove Favourite" : "Favourite",
                symbol: favourited ? "star.slash" : "star") { [weak self] in
                let worked = MusicActions.setFavourited(!favourited)
                self?.reportMusic(worked,
                                  success: favourited ? "Favourite removed" : "Favourited",
                                  successSymbol: favourited ? "star.slash" : "star.fill",
                                  failure: "Couldn't change favourite")
            }

            let playlists = NSMenuItem(title: "Add to Playlist", action: nil, keyEquivalent: "")
            playlists.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: nil)
            let submenu = NSMenu()
            submenu.delegate = self
            playlists.submenu = submenu
            playlistsItem = playlists
            menu.addItem(playlists)

            add(to: menu, title: "Delete from Library", symbol: "trash") { [weak self] in
                guard let self, self.confirmDelete(track) else { return }
                let worked = MusicActions.deleteFromLibrary()
                self.reportMusic(worked, success: "Deleted from library", successSymbol: "trash",
                                 failure: "Couldn't delete it — it may not be in your library")
            }

            add(to: menu, title: "Show in Apple Music", symbol: "music.note.house") { [weak self] in
                self?.reportMusic(MusicActions.revealInMusic(), success: "Showing in Music",
                                  successSymbol: "music.note.house", failure: "Couldn't show it in Music")
            }
            menu.addItem(.separator())
        }

        add(to: menu, title: "Copy Title and Artist", symbol: "doc.on.doc") { [weak self] in
            MusicActions.copyToPasteboard(track)
            self?.model?.show(.success(text: "Copied"))
        }
        if model.nowPlaying.artwork != nil, model.settings.clipboardHistory {
            add(to: menu, title: "Save Artwork to Clipboard", symbol: "photo") { [weak self] in
                guard let self, let model = self.model else { return }
                let saved = model.saveArtworkToClipboard()
                self.report(saved ? "Artwork in Clipboard" : "Couldn't save the artwork",
                            symbol: saved ? "doc.on.clipboard" : "exclamationmark.triangle")
            }
        }
        add(to: menu, title: "Search on YouTube", symbol: "magnifyingglass") {
            MusicActions.search(track, on: "YouTube")
        }
        menu.addItem(.separator())

        if track.bundleID != nil {
            add(to: menu, title: "Open \(appName(for: track.bundleID))", symbol: "arrow.up.forward.app") { [weak self] in
                self?.model?.nowPlaying.openSourceApp()
                self?.model?.collapse()
            }
        }
        add(to: menu, title: "Hide Until Next Song", symbol: "eye.slash") { [weak self] in
            self?.model?.dismissNowPlaying()
        }
        menu.addItem(.separator())
        add(to: menu, title: "Halo Settings…", symbol: "gearshape") { [weak self] in
            self?.model?.collapse()
            self?.model?.openSettings()
        }
        return menu
    }

    private func add(to menu: NSMenu, title: String, symbol: String, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(runItem(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.representedObject = Action(run: action)
        menu.addItem(item)
    }

    private final class Action: NSObject {
        let run: () -> Void
        init(run: @escaping () -> Void) { self.run = run }
    }

    @objc private func runItem(_ sender: NSMenuItem) {
        (sender.representedObject as? Action)?.run()
    }

    /// Deleting cannot be undone from the island, so it is never one stray click away.
    private func confirmDelete(_ track: Track) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete “\(track.title)” from your library?"
        alert.informativeText = track.artist.isEmpty
            ? "This removes the song from your Music library. It can't be undone from Halo."
            : "This removes “\(track.title)” by \(track.artist) from your Music library. It can't be undone from Halo."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        // Cancel is the safe default: Return cancels, and Escape cancels too.
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func report(_ text: String, symbol: String) {
        model?.show(.message(text: text, symbol: symbol))
    }

    /// Reports a Music action, turning "not allowed yet" into something actionable.
    private func reportMusic(_ worked: Bool, success: String, successSymbol: String, failure: String) {
        if worked {
            model?.show(.success(text: success))
        } else if MusicActions.lastFailure == .notAllowed {
            report("Allow Halo to control Music", symbol: "lock.shield")
            MusicActions.openAutomationSettings()
        } else {
            report(failure, symbol: "exclamationmark.triangle")
        }
    }

    // MARK: NSMenuDelegate

    /// The playlists are read when the submenu opens, so the menu itself opens instantly.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === playlistsItem?.submenu else { return }
        menu.removeAllItems()
        let playlists = MusicActions.playlists()
        guard !playlists.isEmpty else {
            let empty = NSMenuItem(title: "No playlists", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for playlist in playlists.prefix(40) {
            add(to: menu, title: playlist, symbol: "music.note.list") { [weak self] in
                let worked = MusicActions.add(toPlaylist: playlist)
                self?.reportMusic(worked, success: "Added to \(playlist)", successSymbol: "text.badge.plus",
                                  failure: "Couldn't add to \(playlist)")
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu.supermenu == nil else { return }
        model?.setMenuOpen(false)
        Self.presented = nil
    }
}
