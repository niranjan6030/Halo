import ServiceManagement

/// Open at login, through the same mechanism System Settings › Login Items uses.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
