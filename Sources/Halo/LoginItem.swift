import ServiceManagement

/// Open at login, through the same mechanism System Settings › Login Items uses.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS can accept the registration and still hold it until the user approves it
    /// in Login Items. That is not the same as being switched off, and re-registering
    /// will not clear it — only the user can.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static var statusName: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notRegistered: return "notRegistered"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            islandLog.error("login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
