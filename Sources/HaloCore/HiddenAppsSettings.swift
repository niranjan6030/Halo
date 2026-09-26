import AppKit
import SwiftUI

/// The list of apps the island keeps out of the way of.
struct HiddenAppsSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Section {
            ForEach(settings.hiddenApps, id: \.self) { id in
                HStack(spacing: 10) {
                    if let icon = HiddenApps.icon(for: id) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "questionmark.app.dashed")
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.secondary)
                    }
                    Text(HiddenApps.name(for: id))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Remove") { settings.hiddenApps.removeAll { $0 == id } }
                        .buttonStyle(.link)
                }
            }

            Button {
                add()
            } label: {
                Label("Add App…", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Hide In")
        } footer: {
            Text("While one of these apps is in front, the island stays out of the way entirely — no pop-ups, nothing over the notch. Useful for anything whose own controls live up there, like a video editor or a game.")
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose apps the island should stay out of the way of."
        guard panel.runModal() == .OK else { return }
        var list = settings.hiddenApps
        for url in panel.urls {
            guard let id = HiddenApps.identifier(atPath: url.path), !list.contains(id) else { continue }
            list.append(id)
        }
        settings.hiddenApps = list
    }
}
