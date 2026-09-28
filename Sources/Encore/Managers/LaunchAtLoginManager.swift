import ServiceManagement

/// Thin wrapper around SMAppService for registering Encore as a login item.
enum LaunchAtLoginManager {
    typealias Status = SMAppService.Status

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return nil }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status != .notRegistered else { return nil }
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static var status: Status {
        SMAppService.mainApp.status
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
