import AppKit
import ApplicationServices

struct MenuBarItem: Identifiable, @unchecked Sendable {
    let id: String
    let applicationName: String
    let bundleIdentifier: String
    let label: String
    let pid: pid_t
    let menuIndex: Int
    let accessibilityIdentifier: String?
    let windowID: CGWindowID?
    let eventTargetPID: pid_t
    let frame: CGRect
    let icon: NSImage
    let element: AXUIElement

    var isSystemItem: Bool {
        bundleIdentifier.hasPrefix("com.apple.")
    }

    var isLockedInFirstRow: Bool {
        guard bundleIdentifier == "com.apple.controlcenter" else { return false }
        return accessibilityIdentifier == "com.apple.menuextra.controlcenter"
            || accessibilityIdentifier == "com.apple.menuextra.clock"
    }

    var requiresDirectedActivation: Bool {
        bundleIdentifier == "com.electron.dockerdesktop"
    }

    var requiresPassiveActivationDismissal: Bool {
        bundleIdentifier == "com.apple.TextInputMenuAgent"
    }
}

extension CGRect {
    var quartzCenter: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
