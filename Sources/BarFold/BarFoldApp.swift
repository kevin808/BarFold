import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct BarFoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var shelfController: ShelfPanelController!
    private var settingsController: SettingsWindowController!
    private var hidingController: MenuBarHidingController!
    private let reorderService = MenuBarReorderService()
    private var refreshTimer: Timer?
    private var isMenuBarLayoutReady = false
    private var activationSessionID: UUID?
    private var activationEventMonitor: Any?
    private var inputSourceObserver: NSObjectProtocol?
    private var activationCollapseTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLogger.shared.ensureLogFile()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        DiagnosticLogger.shared.log(
            "app launched version=\(version) build=\(build) pid=\(ProcessInfo.processInfo.processIdentifier) "
                + "macOS=\(ProcessInfo.processInfo.operatingSystemVersionString.debugDescription)"
        )
        NSApp.setActivationPolicy(.accessory)
        prepareStatusItemPlacement()
        configureStatusItem()

        hidingController = MenuBarHidingController()
        settingsController = SettingsWindowController(model: model) { [weak self] in
            guard let self,
                  self.model.pendingFoldIDs.isEmpty else { return }
            self.finishActivationSession(reason: "settings-closed")
        }
        shelfController = ShelfPanelController(model: model) { [weak self] in
            self?.showSettings()
        }

        model.onRequestToggleShelf = { [weak self] in self?.toggleShelf() }
        model.onRequestCloseShelf = { [weak self] in self?.shelfController.close() }
        model.onRequestActivate = { [weak self] item, completion in
            guard let self else {
                completion(false)
                return
            }
            self.beginActivationSession(item: item, completion: completion)
        }
        model.onRequestOpenApplication = { [weak self] item, completion in
            guard let self else {
                completion(false)
                return
            }
            self.openApplication(item: item, completion: completion)
        }
        model.onRequestFoldChange = { [weak self] item, folded, completion in
            guard let self else {
                completion(false)
                return
            }
            self.finishActivationSession(reason: "organization-started")
            let destinationName = folded ? "second-row" : "first-row"
            DiagnosticLogger.shared.log(
                "organization expand requested item=\(item.label.debugDescription) destination=\(destinationName)"
            )
            self.hidingController.expandForOrganization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self,
                      let separatorFrame = self.hidingController.separatorFrameInQuartzCoordinates() else {
                    DiagnosticLogger.shared.log(
                        "organization failed item=\(item.label.debugDescription) stage=separator-frame-unavailable"
                    )
                    completion(false)
                    self?.hidingController.collapse()
                    return
                }
                self.reorderService.move(
                    item: item,
                    intoHiddenSection: folded,
                    separatorFrame: separatorFrame,
                    separatorWindowID: self.hidingController.separatorWindowID
                ) { [weak self] succeeded in
                    guard let self else {
                        completion(succeeded)
                        return
                    }
                    self.hidingController.collapse()
                    DiagnosticLogger.shared.log(
                        "organization collapsed item=\(item.label.debugDescription) moveSucceeded=\(succeeded)"
                    )
                    // WindowServer needs a short settling period after the separator collapses;
                    // scanning earlier can cache nil window IDs for items beyond the notch.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        completion(succeeded)
                    }
                }
            }
        }

        hidingController.setEnabled(true)
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
        if CommandLine.arguments.contains("--show-shelf") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.toggleShelf()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            self.isMenuBarLayoutReady = true
            let statusFrame = self.statusItem.button?.window?.frame.debugDescription ?? "nil"
            DiagnosticLogger.shared.log("status item frame=\(statusFrame)")
            DiagnosticLogger.shared.log("startup layout ready delay=0.75s")
            self.model.scan()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.scan() }
        }
        scheduleDiagnosticItemActionIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        finishActivationSession(reason: "app-terminating")
        DiagnosticLogger.shared.log("app terminating")
        refreshTimer?.invalidate()
    }

    private func prepareStatusItemPlacement() {
        let defaults = UserDefaults.standard
        let migrationKey = "statusItemPlacementVersion"

        // Keep the main control anchored at the right even if section reordering
        // causes macOS to renumber status item positions.
        defaults.set(CGFloat(0), forKey: "NSStatusItem Preferred Position BarFold.Toggle.v3")
        guard defaults.integer(forKey: migrationKey) < 3 else { return }

        defaults.set(CGFloat(1), forKey: "NSStatusItem Preferred Position BarFold.SectionDivider.v3")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position BarFold.Toggle.v2")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position BarFold.SectionDivider.v2")
        defaults.removeObject(forKey: "NSStatusItem VisibleCC BarFold.Toggle.v2")
        defaults.removeObject(forKey: "NSStatusItem VisibleCC BarFold.SectionDivider.v2")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position BarFold.Toggle")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position BarFold.SectionDivider")
        defaults.removeObject(forKey: "NSStatusItem VisibleCC BarFold.Toggle")
        defaults.removeObject(forKey: "NSStatusItem VisibleCC BarFold.SectionDivider")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position Item-0")
        defaults.removeObject(forKey: "NSStatusItem Visible Item-0")
        defaults.set(3, forKey: migrationKey)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "BarFold.Toggle.v3"
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right",
            accessibilityDescription: "BarFold"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "BarFold"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleShelf()
        }
    }

    private func toggleShelf() {
        if activationSessionID != nil {
            finishActivationSession(reason: "shelf-toggled")
        }
        if !model.isTrusted {
            model.requestAccessibility()
        }
        let wasVisible = shelfController.isVisible
        shelfController.toggle(relativeTo: statusItem.button)
        DiagnosticLogger.shared.log(
            "shelf toggled wasVisible=\(wasVisible) isVisible=\(shelfController.isVisible)"
        )
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: shelfController.isVisible ? "收起第二行" : "展开第二行", action: #selector(toggleShelfFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "刷新", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 BarFold", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleShelfFromMenu() { toggleShelf() }
    @objc private func refresh() { model.scan() }
    @objc private func showSettingsFromMenu() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showSettings() {
        finishActivationSession(reason: "settings-opened")
        shelfController.close()
        model.refreshLoginItemState()
        settingsController.show()
        if isMenuBarLayoutReady {
            model.scan()
        }
    }

    private func beginActivationSession(
        item: MenuBarItem,
        completion: @escaping (Bool) -> Void
    ) {
        finishActivationSession(reason: "activation-replaced")
        let sessionID = UUID()
        activationSessionID = sessionID
        hidingController.expandForOrganization()
        DiagnosticLogger.shared.log(
            "activation layout expanded item=\(item.label.debugDescription) session=\(sessionID.uuidString)"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.activationSessionID == sessionID else {
                completion(false)
                return
            }
            self.reorderService.activate(item: item) { [weak self] succeeded in
                guard let self else {
                    completion(succeeded)
                    return
                }
                completion(succeeded)
                guard self.activationSessionID == sessionID else { return }
                if succeeded {
                    if item.requiresPassiveActivationDismissal {
                        self.armInputMethodDismissal(sessionID: sessionID)
                    } else {
                        self.armActivationDismissal(sessionID: sessionID)
                    }
                } else {
                    self.finishActivationSession(reason: "activation-failed")
                }
            }
        }
    }

    private func openApplication(
        item: MenuBarItem,
        completion: @escaping (Bool) -> Void
    ) {
        if item.isSystemItem {
            openSystemSettings(for: item, completion: completion)
            return
        }
        if item.bundleIdentifier == "com.Snipaste",
           let application = NSRunningApplication(processIdentifier: item.pid) {
            _ = application.activate(options: [])
            DiagnosticLogger.shared.log(
                "application command activation requested item=\(item.label.debugDescription) "
                    + "command=preferences delay=0.2s"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                guard self.pressStatusMenuCommand(
                    item: item,
                    titlePrefixes: ["首选项", "Preferences"]
                ) else {
                    completion(false)
                    return
                }
                DiagnosticLogger.shared.log(
                    "application command invoked item=\(item.label.debugDescription) "
                        + "command=preferences menuDisplayed=false"
                )
                self.waitForVisibleApplicationWindow(
                    item: item,
                    launchedApplication: application,
                    attemptsRemaining: 40,
                    completion: completion
                )
            }
            return
        }

        guard let applicationURL = launchURL(for: item) else {
            DiagnosticLogger.shared.log(
                "application URL unavailable item=\(item.label.debugDescription) "
                    + "bundle=\(item.bundleIdentifier.debugDescription)"
            )
            completion(false)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        DiagnosticLogger.shared.log(
            "application launching item=\(item.label.debugDescription) url=\(applicationURL.path.debugDescription)"
        )
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { application, error in
            DispatchQueue.main.async {
                if let error {
                    DiagnosticLogger.shared.log(
                        "application launch failed item=\(item.label.debugDescription) "
                            + "error=\(error.localizedDescription.debugDescription)"
                    )
                    completion(false)
                    return
                }
                guard let application else {
                    DiagnosticLogger.shared.log(
                        "application launch failed item=\(item.label.debugDescription) reason=no-running-application"
                    )
                    completion(false)
                    return
                }
                _ = application.activate(options: [.activateAllWindows])
                self.waitForVisibleApplicationWindow(
                    item: item,
                    launchedApplication: application,
                    attemptsRemaining: 12,
                    completion: completion
                )
            }
        }
    }

    private func launchURL(for item: MenuBarItem) -> URL? {
        if item.bundleIdentifier.hasPrefix("com.bjango.istatmenus"),
           let applicationURL = NSWorkspace.shared.urlForApplication(
               withBundleIdentifier: "com.bjango.istatmenus"
           ) {
            return applicationURL
        }

        let candidate = NSRunningApplication(processIdentifier: item.pid)?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier)
        guard let candidate else { return nil }

        // Docker.app is the background engine wrapper. Its nested Electron app
        // owns the actual Dashboard window and must receive the reopen event.
        if item.bundleIdentifier == "com.electron.dockerdesktop" {
            return candidate
        }

        let components = candidate.standardizedFileURL.pathComponents
        var currentURL = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst() {
            currentURL.appendPathComponent(component)
            if component.lowercased().hasSuffix(".app") {
                return currentURL
            }
        }
        return candidate
    }

    private func openSystemSettings(
        for item: MenuBarItem,
        completion: @escaping (Bool) -> Void
    ) {
        let destination = item.bundleIdentifier == "com.apple.TextInputMenuAgent"
            ? "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
            : "x-apple.systempreferences:"
        guard let settingsURL = URL(string: destination) else {
            DiagnosticLogger.shared.log(
                "system settings open failed item=\(item.label.debugDescription) reason=invalid-url"
            )
            completion(false)
            return
        }
        let opened = NSWorkspace.shared.open(settingsURL)
        DiagnosticLogger.shared.log(
            "system settings open completed item=\(item.label.debugDescription) "
                + "destination=\(destination.debugDescription) succeeded=\(opened)"
        )
        completion(opened)
    }

    private func pressStatusMenuCommand(
        item: MenuBarItem,
        titlePrefixes: [String]
    ) -> Bool {
        let applicationElement = AXUIElementCreateApplication(item.pid)
        let roots = [accessibilityElement(
            attribute: kAXExtrasMenuBarAttribute,
            from: applicationElement
        ), item.element].compactMap { $0 }

        for root in roots {
            guard let command = findMenuItem(
                in: root,
                titlePrefixes: titlePrefixes,
                depthRemaining: 6
            ) else { continue }
            let result = AXUIElementPerformAction(command, kAXPressAction as CFString)
            DiagnosticLogger.shared.log(
                "application command AXPress item=\(item.label.debugDescription) "
                    + "result=\(result.rawValue)"
            )
            return result == .success
        }
        DiagnosticLogger.shared.log(
            "application command unavailable item=\(item.label.debugDescription) "
                + "commands=\(titlePrefixes)"
        )
        return false
    }

    private func findMenuItem(
        in element: AXUIElement,
        titlePrefixes: [String],
        depthRemaining: Int
    ) -> AXUIElement? {
        guard depthRemaining >= 0 else { return nil }
        if accessibilityString(attribute: kAXRoleAttribute, from: element) == kAXMenuItemRole {
            let title = accessibilityString(attribute: kAXTitleAttribute, from: element)
            if titlePrefixes.contains(where: {
                title.range(
                    of: $0,
                    options: [.caseInsensitive, .anchored],
                    locale: .current
                ) != nil
            }) {
                return element
            }
        }
        for child in accessibilityChildren(of: element) {
            if let match = findMenuItem(
                in: child,
                titlePrefixes: titlePrefixes,
                depthRemaining: depthRemaining - 1
            ) {
                return match
            }
        }
        return nil
    }

    private func accessibilityElement(
        attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return (value as! AXUIElement?)
    }

    private func accessibilityString(
        attribute: String,
        from element: AXUIElement
    ) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return "" }
        return value as? String ?? ""
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func waitForVisibleApplicationWindow(
        item: MenuBarItem,
        launchedApplication: NSRunningApplication,
        attemptsRemaining: Int,
        completion: @escaping (Bool) -> Void
    ) {
        var candidatePIDs: Set<pid_t> = [item.pid, launchedApplication.processIdentifier]
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == item.bundleIdentifier }
            .forEach { candidatePIDs.insert($0.processIdentifier) }

        if let frame = visibleApplicationWindowFrame(ownerPIDs: candidatePIDs) {
            DiagnosticLogger.shared.log(
                "application visible window item=\(item.label.debugDescription) "
                    + "frame=\(frame.debugDescription) pids=\(candidatePIDs.sorted())"
            )
            completion(true)
            return
        }

        guard attemptsRemaining > 1 else {
            DiagnosticLogger.shared.log(
                "application launch failed item=\(item.label.debugDescription) reason=no-visible-window "
                    + "pids=\(candidatePIDs.sorted())"
            )
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForVisibleApplicationWindow(
                item: item,
                launchedApplication: launchedApplication,
                attemptsRemaining: attemptsRemaining - 1,
                completion: completion
            )
        }
    }

    private func visibleApplicationWindowFrame(ownerPIDs: Set<pid_t>) -> CGRect? {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return windows.compactMap { window -> CGRect? in
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPIDs.contains(ownerPID),
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = bounds["X"]?.doubleValue,
                  let y = bounds["Y"]?.doubleValue,
                  let width = bounds["Width"]?.doubleValue,
                  let height = bounds["Height"]?.doubleValue else { return nil }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            guard
                  frame.width >= 120,
                  frame.height >= 80 else { return nil }
            return frame
        }.first
    }

    private func armActivationDismissal(sessionID: UUID) {
        armActivationTimeout(sessionID: sessionID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.activationSessionID == sessionID else { return }
            self.activationEventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseUp, .rightMouseUp, .keyUp]
            ) { [weak self] event in
                let eventType = event.type.rawValue
                let eventUserData = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
                guard eventUserData != BarFoldSyntheticEvent.userData else {
                    DiagnosticLogger.shared.log(
                        "activation interaction ignored eventType=\(eventType) reason=barfold-synthetic-event"
                    )
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self, self.activationSessionID == sessionID else { return }
                    if let monitor = self.activationEventMonitor {
                        NSEvent.removeMonitor(monitor)
                        self.activationEventMonitor = nil
                    }
                    DiagnosticLogger.shared.log(
                        "activation interaction completed eventType=\(eventType) "
                            + "session=\(sessionID.uuidString) collapseDelay=0.45s"
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                        guard let self, self.activationSessionID == sessionID else { return }
                        self.finishActivationSession(reason: "user-interaction-completed")
                    }
                }
            }
        }
    }

    private func armInputMethodDismissal(sessionID: UUID) {
        armActivationTimeout(sessionID: sessionID)
        let initialInputSourceID = currentInputSourceIdentifier()
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activationSessionID == sessionID else { return }
                let currentInputSourceID = self.currentInputSourceIdentifier()
                guard let initialInputSourceID,
                      let currentInputSourceID,
                      currentInputSourceID != initialInputSourceID else {
                    DiagnosticLogger.shared.log(
                        "input method selection notification ignored session=\(sessionID.uuidString) "
                            + "initial=\(initialInputSourceID.debugDescription) "
                            + "current=\(currentInputSourceID.debugDescription)"
                    )
                    return
                }
                if let observer = self.inputSourceObserver {
                    DistributedNotificationCenter.default().removeObserver(observer)
                    self.inputSourceObserver = nil
                }
                DiagnosticLogger.shared.log(
                    "input method selection changed session=\(sessionID.uuidString) collapseDelay=0.4s"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.activationSessionID == sessionID else { return }
                    self.finishActivationSession(reason: "input-source-selection-changed")
                }
            }
        }
        DiagnosticLogger.shared.log(
            "input method passive dismissal armed session=\(sessionID.uuidString) "
                + "initial=\(initialInputSourceID.debugDescription) timeout=30s"
        )
    }

    private func currentInputSourceIdentifier() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    private func armActivationTimeout(sessionID: UUID) {
        activationCollapseTimer?.invalidate()
        activationCollapseTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activationSessionID == sessionID else { return }
                self.finishActivationSession(reason: "activation-timeout")
            }
        }
    }

    private func finishActivationSession(reason: String) {
        let sessionID = activationSessionID
        activationSessionID = nil
        if let monitor = activationEventMonitor {
            NSEvent.removeMonitor(monitor)
            activationEventMonitor = nil
        }
        if let observer = inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            inputSourceObserver = nil
        }
        activationCollapseTimer?.invalidate()
        activationCollapseTimer = nil
        hidingController.collapse()
        if let sessionID {
            DiagnosticLogger.shared.log(
                "activation layout collapsed reason=\(reason) session=\(sessionID.uuidString)"
            )
        }
    }

    private enum DiagnosticItemAction {
        case nativeMenu
        case openApplication

        var option: String {
            switch self {
            case .nativeMenu: "--activate-bundle"
            case .openApplication: "--open-bundle"
            }
        }

        var name: String {
            switch self {
            case .nativeMenu: "native-menu"
            case .openApplication: "open-application"
            }
        }
    }

    private func scheduleDiagnosticItemActionIfRequested() {
        let arguments = CommandLine.arguments
        for action in [DiagnosticItemAction.nativeMenu, .openApplication] {
            guard let optionIndex = arguments.firstIndex(of: action.option),
                  arguments.indices.contains(optionIndex + 1) else { continue }
            let bundleIdentifier = arguments[optionIndex + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.runDiagnosticItemAction(
                    action,
                    bundleIdentifier: bundleIdentifier,
                    attemptsRemaining: 12
                )
            }
        }
    }

    private func runDiagnosticItemAction(
        _ action: DiagnosticItemAction,
        bundleIdentifier: String,
        attemptsRemaining: Int
    ) {
        if let item = model.items.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            DiagnosticLogger.shared.log(
                "diagnostic item action running action=\(action.name) "
                    + "bundle=\(bundleIdentifier.debugDescription) item=\(item.label.debugDescription)"
            )
            switch action {
            case .nativeMenu:
                model.activate(item)
            case .openApplication:
                model.openApplication(item)
            }
            return
        }
        guard attemptsRemaining > 1 else {
            DiagnosticLogger.shared.log(
                "diagnostic item action skipped action=\(action.name) "
                    + "bundle=\(bundleIdentifier.debugDescription) reason=item-not-found"
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.runDiagnosticItemAction(
                action,
                bundleIdentifier: bundleIdentifier,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }
}
