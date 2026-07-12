import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var isTrusted = false
    @Published private(set) var isScanning = false
    @Published private(set) var foldedIDs: Set<String>
    @Published private(set) var pendingFoldIDs: Set<String> = []
    @Published private(set) var launchAtLogin = false
    @Published var lastError: String?

    var onRequestToggleShelf: (() -> Void)?
    var onRequestCloseShelf: (() -> Void)?
    var onRequestFoldChange: ((MenuBarItem, Bool, @escaping (Bool) -> Void) -> Void)?
    var onRequestActivate: ((MenuBarItem, @escaping (Bool) -> Void) -> Void)?
    var onRequestOpenApplication: ((MenuBarItem, @escaping (Bool) -> Void) -> Void)?

    private let scanner = MenuBarScanner()
    private let defaults = UserDefaults.standard
    private let scanQueue = DispatchQueue(label: "com.local.BarFold.scan", qos: .utility)

    private enum Keys {
        static let foldedIDs = "foldedItemIDs"
        static let configured = "hasConfiguredItems"
        static let itemIDVersion = "itemIDVersion"
        static let settingsItemOrder = "settingsItemOrder"
    }

    init() {
        foldedIDs = Set(defaults.stringArray(forKey: Keys.foldedIDs) ?? [])
        refreshLoginItemState()
    }

    var foldedItems: [MenuBarItem] {
        items.filter { foldedIDs.contains($0.id) }
    }

    func scan(promptForPermission: Bool = false) {
        guard !isScanning, pendingFoldIDs.isEmpty else { return }
        isTrusted = scanner.isTrusted(prompt: promptForPermission)
        guard isTrusted else {
            DiagnosticLogger.shared.log("scan skipped reason=accessibility-not-trusted prompt=\(promptForPermission)")
            items = []
            return
        }

        isScanning = true
        let scanner = scanner
        scanQueue.async { [weak self] in
            let scannedItems = scanner.scan()
            DispatchQueue.main.async {
                self?.applyScanResult(scannedItems)
            }
        }
    }

    private func applyScanResult(_ scannedItems: [MenuBarItem]) {
        items = itemsInStableSettingsOrder(scannedItems)
        isScanning = false

        if !defaults.bool(forKey: Keys.configured) {
            let initialOrder = scannedItems.map(\.id)
            foldedIDs = Set(initialOrder)
            defaults.set(initialOrder, forKey: Keys.foldedIDs)
            defaults.set(true, forKey: Keys.configured)
            defaults.set(2, forKey: Keys.itemIDVersion)
        } else if defaults.integer(forKey: Keys.itemIDVersion) < 2 {
            let selectedBundles = Set(foldedIDs.compactMap { id in
                id.split(separator: "|", maxSplits: 1).first.map(String.init)
            })
            let migratedOrder = scannedItems
                .filter { selectedBundles.contains($0.bundleIdentifier) }
                .map(\.id)
            foldedIDs = Set(migratedOrder)
            defaults.set(migratedOrder, forKey: Keys.foldedIDs)
            defaults.set(2, forKey: Keys.itemIDVersion)
        }

        keepLockedItemsInFirstRow(scannedItems)
    }

    func requestAccessibility() {
        scan(promptForPermission: true)
        if !isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.scan()
            }
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealDiagnosticLog() {
        DiagnosticLogger.shared.ensureLogFile()
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLogger.logURL])
    }

    func setFolded(_ folded: Bool, item: MenuBarItem) {
        guard !item.isLockedInFirstRow else {
            DiagnosticLogger.shared.log(
                "selection ignored item=\(item.label.debugDescription) id=\(item.id.debugDescription) reason=system-locked"
            )
            return
        }
        guard !pendingFoldIDs.contains(item.id) else { return }
        let wasFolded = foldedIDs.contains(item.id)
        guard wasFolded != folded else { return }

        if folded {
            foldedIDs.insert(item.id)
        } else {
            foldedIDs.remove(item.id)
        }
        persistFoldedIDs()
        pendingFoldIDs.insert(item.id)
        let destinationName = folded ? "second-row" : "first-row"
        DiagnosticLogger.shared.log(
            "selection changed item=\(item.label.debugDescription) id=\(item.id.debugDescription) "
                + "destination=\(destinationName)"
        )

        guard let onRequestFoldChange else {
            pendingFoldIDs.remove(item.id)
            DiagnosticLogger.shared.log("selection rollback item=\(item.label.debugDescription) reason=no-move-handler")
            return
        }
        onRequestFoldChange(item, folded) { [weak self] succeeded in
            guard let self else { return }
            self.pendingFoldIDs.remove(item.id)
            if !succeeded {
                if wasFolded {
                    self.foldedIDs.insert(item.id)
                } else {
                    self.foldedIDs.remove(item.id)
                }
                self.persistFoldedIDs()
                self.lastError = "无法移动“\(item.label)”。该项目可能不支持菜单栏重排。"
                DiagnosticLogger.shared.log(
                    "selection rollback item=\(item.label.debugDescription) id=\(item.id.debugDescription) reason=move-failed"
                )
            } else {
                DiagnosticLogger.shared.log(
                    "selection committed item=\(item.label.debugDescription) id=\(item.id.debugDescription)"
                )
            }
            self.scan()
        }
    }

    func moveFoldedItem(from sourceID: String, before destinationID: String) {
        var order = persistedOrder()
        order.removeAll { $0 == sourceID }
        if let destinationIndex = order.firstIndex(of: destinationID) {
            order.insert(sourceID, at: destinationIndex)
        } else {
            order.append(sourceID)
        }
        defaults.set(order, forKey: Keys.foldedIDs)
        foldedIDs = Set(order)
        objectWillChange.send()
    }

    func orderedFoldedItems() -> [MenuBarItem] {
        let positions = Dictionary(uniqueKeysWithValues: persistedOrder().enumerated().map { ($1, $0) })
        return foldedItems.sorted {
            (positions[$0.id] ?? Int.max) < (positions[$1.id] ?? Int.max)
        }
    }

    func activate(_ item: MenuBarItem) {
        onRequestCloseShelf?()
        DiagnosticLogger.shared.log(
            "activation requested item=\(item.label.debugDescription) id=\(item.id.debugDescription)"
        )
        guard let onRequestActivate else {
            lastError = "无法打开“\(item.label)”。请刷新后重试。"
            DiagnosticLogger.shared.log(
                "activation failed item=\(item.label.debugDescription) reason=no-activation-handler"
            )
            return
        }
        onRequestActivate(item) { [weak self] succeeded in
            guard let self else { return }
            if succeeded {
                DiagnosticLogger.shared.log(
                    "activation completed item=\(item.label.debugDescription) succeeded=true"
                )
            } else {
                self.lastError = "无法打开“\(item.label)”。请刷新后重试。"
                DiagnosticLogger.shared.log(
                    "activation completed item=\(item.label.debugDescription) succeeded=false"
                )
            }
        }
    }

    func openApplication(_ item: MenuBarItem) {
        onRequestCloseShelf?()
        DiagnosticLogger.shared.log(
            "application open requested item=\(item.label.debugDescription) "
                + "bundle=\(item.bundleIdentifier.debugDescription)"
        )
        guard let onRequestOpenApplication else {
            lastError = "无法打开“\(item.label)”。请刷新后重试。"
            DiagnosticLogger.shared.log(
                "application open failed item=\(item.label.debugDescription) reason=no-open-handler"
            )
            return
        }
        onRequestOpenApplication(item) { [weak self] succeeded in
            guard let self else { return }
            if succeeded {
                DiagnosticLogger.shared.log(
                    "application open completed item=\(item.label.debugDescription) succeeded=true"
                )
            } else {
                self.lastError = "无法打开“\(item.label)”。该菜单栏项目没有可打开的应用窗口。"
                DiagnosticLogger.shared.log(
                    "application open completed item=\(item.label.debugDescription) succeeded=false "
                        + "nativeMenuFallback=false"
                )
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemState()
        } catch {
            lastError = error.localizedDescription
            refreshLoginItemState()
        }
    }

    func refreshLoginItemState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func persistFoldedIDs() {
        var order = persistedOrder().filter { foldedIDs.contains($0) }
        let known = Set(order)
        order.append(contentsOf: foldedIDs.filter { !known.contains($0) }.sorted())
        defaults.set(order, forKey: Keys.foldedIDs)
    }

    private func persistedOrder() -> [String] {
        defaults.stringArray(forKey: Keys.foldedIDs) ?? Array(foldedIDs)
    }

    private func itemsInStableSettingsOrder(_ scannedItems: [MenuBarItem]) -> [MenuBarItem] {
        let savedOrder = defaults.stringArray(forKey: Keys.settingsItemOrder) ?? []
        var seenIDs: Set<String> = []
        var order = savedOrder.filter { seenIDs.insert($0).inserted }
        let newIDs = scannedItems.map(\.id).filter { seenIDs.insert($0).inserted }
        order.append(contentsOf: newIDs)

        if order != savedOrder {
            defaults.set(order, forKey: Keys.settingsItemOrder)
            DiagnosticLogger.shared.log(
                "settings order updated total=\(order.count) appended=\(newIDs.count)"
            )
        }

        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return scannedItems.sorted {
            (positions[$0.id] ?? Int.max) < (positions[$1.id] ?? Int.max)
        }
    }

    private func keepLockedItemsInFirstRow(_ scannedItems: [MenuBarItem]) {
        let lockedIDs = Set(scannedItems.filter(\.isLockedInFirstRow).map(\.id))
        let removedIDs = foldedIDs.intersection(lockedIDs)
        guard !removedIDs.isEmpty else { return }

        foldedIDs.subtract(removedIDs)
        persistFoldedIDs()
        DiagnosticLogger.shared.log(
            "locked items removed from second-row selection count=\(removedIDs.count)"
        )
    }
}
