import AppKit
import SwiftUI

@MainActor
final class ShelfPanelController {
    private var panel: NSPanel!
    private let model: AppModel
    private let openSettings: () -> Void
    private var globalMouseMonitor: Any?
    private var localEventMonitor: Any?
    private var dismissExclusionFrame: NSRect?

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ShelfView(
            model: model,
            openSettings: openSettings,
            collapse: { [weak self] in self?.close() }
        ))
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if panel.isVisible {
            close()
        } else {
            show(relativeTo: statusButton)
        }
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        let screen = statusButton?.window?.screen ?? NSScreen.main
        guard let screen else { return }
        let itemCount = max(model.orderedFoldedItems().count, 3)
        let width = min(max(CGFloat(itemCount * 38 + 150), 330), min(760, screen.visibleFrame.width - 24))
        let height: CGFloat = 48
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let x = min(
            screen.visibleFrame.maxX - width - 10,
            (statusButton?.window?.frame.maxX ?? screen.visibleFrame.maxX) - width
        )
        let y = screen.frame.maxY - menuBarHeight - height - 5
        dismissExclusionFrame = statusButton?.window?.frame.insetBy(dx: -3, dy: -3)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
        startDismissMonitoring()
    }

    func close() {
        guard panel.isVisible || globalMouseMonitor != nil || localEventMonitor != nil else { return }
        panel.orderOut(nil)
        stopDismissMonitoring()
        dismissExclusionFrame = nil
    }

    private func startDismissMonitoring() {
        stopDismissMonitoring()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            let location = NSEvent.mouseLocation
            DispatchQueue.main.async {
                guard let self,
                      !self.isDismissExclusion(location) else { return }
                self.close()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown,
               !self.panel.frame.contains(NSEvent.mouseLocation),
               !self.isDismissExclusion(NSEvent.mouseLocation) {
                self.close()
            }
            return event
        }
    }

    private func stopDismissMonitoring() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    private func isDismissExclusion(_ location: NSPoint) -> Bool {
        dismissExclusionFrame?.contains(location) == true
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let content = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = model.text(.settingsWindowTitle)
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        model.onLanguageChange = { [weak window, weak model] in
            window?.title = model?.text(.settingsWindowTitle) ?? "BarFold"
        }
    }

    required init?(coder: NSCoder) { nil }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class MenuBarHidingController {
    private let separatorItem: NSStatusItem
    private(set) var isExpandedForOrganization = false
    private var isEnabled = false

    init() {
        separatorItem = NSStatusBar.system.statusItem(withLength: 18)
        separatorItem.autosaveName = "BarFold.SectionDivider.v3"
        configureSeparator()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        separatorItem.isVisible = enabled
        if enabled {
            isExpandedForOrganization ? expandForOrganization() : collapse()
        }
    }

    func expandForOrganization() {
        guard isEnabled else { return }
        isExpandedForOrganization = true
        separatorItem.length = 1
        if let button = separatorItem.button {
            button.image = nil
            button.cell?.isEnabled = false
            button.toolTip = nil
        }
    }

    func collapse() {
        guard isEnabled else { return }
        isExpandedForOrganization = false
        separatorItem.length = collapsedLength
        if let button = separatorItem.button {
            button.image = nil
            button.cell?.isEnabled = false
            button.isHighlighted = false
            button.toolTip = nil
        }
    }

    private var collapsedLength: CGFloat {
        let widestScreen = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        return max(500, min(widestScreen * 2, 10_000))
    }

    private func configureSeparator() {
        guard let button = separatorItem.button else { return }
        button.image = nil
        button.cell?.isEnabled = false
    }

    func separatorFrameInQuartzCoordinates() -> CGRect? {
        guard let window = separatorItem.button?.window,
              let screen = window.screen,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        let frame = window.frame
        return CGRect(
            x: displayBounds.minX + frame.minX - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    var separatorWindowID: CGWindowID? {
        if let windowNumber = separatorItem.button?.window?.windowNumber,
           let windowID = CGWindowID(exactly: windowNumber),
           windowID != 0 {
            return windowID
        }

        guard let separatorFrame = separatorFrameInQuartzCoordinates() else { return nil }
        return MenuBarWindowBridge.windows()
            .min {
                windowDistance($0.frame, separatorFrame) < windowDistance($1.frame, separatorFrame)
            }?.id
    }

    private func windowDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.midX - rhs.midX)
            + abs(lhs.midY - rhs.midY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    @objc private func screenParametersChanged() {
        if isEnabled && !isExpandedForOrganization {
            collapse()
        }
    }
}
