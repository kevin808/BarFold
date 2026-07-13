import AppKit
import ApplicationServices

private struct ScannedItemCandidate {
    let id: String
    let applicationName: String
    let bundleIdentifier: String
    let label: String
    let pid: pid_t
    let menuIndex: Int
    let accessibilityIdentifier: String?
    let frame: CGRect
    let icon: NSImage
    let element: AXUIElement
}

struct MenuBarWindowMatchCandidate {
    let frame: CGRect
    let expectedTitles: Set<String>
}

enum MenuBarWindowMatcher {
    static func match(
        candidates: [MenuBarWindowMatchCandidate],
        availableWindows: [MenuBarWindowBridge.WindowRecord]
    ) -> [MenuBarWindowBridge.WindowRecord?] {
        var windows = availableWindows
            .filter { $0.frame.width > 2 && $0.frame.width < 200 && $0.frame.height < 60 }
        return candidates.map { candidate in
            let nearestIndex = windows.indices.min {
                MenuBarWindowBridge.matchDistance(windows[$0].frame, candidate.frame)
                    < MenuBarWindowBridge.matchDistance(windows[$1].frame, candidate.frame)
            }

            let index: Int?
            if let nearestIndex,
               MenuBarWindowBridge.matchDistance(windows[nearestIndex].frame, candidate.frame) <= 20 {
                index = nearestIndex
            } else {
                index = windows.indices
                    .filter { windowIndex in
                        windows[windowIndex].title.map(candidate.expectedTitles.contains) == true
                    }
                    .min {
                        MenuBarWindowBridge.matchDistance(windows[$0].frame, candidate.frame)
                            < MenuBarWindowBridge.matchDistance(windows[$1].frame, candidate.frame)
                    }
            }

            guard let index else { return nil }
            return windows.remove(at: index)
        }
    }
}

final class MenuBarScanner: @unchecked Sendable {
    private var lastDiagnosticSignature: String?

    func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func scan() -> [MenuBarItem] {
        guard isTrusted(prompt: false) else { return [] }

        var candidates: [ScannedItemCandidate] = []
        let availableWindows = MenuBarWindowBridge.windows()
        let applications = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        for application in applications {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.35)
            guard let extras: AXUIElement = value(of: kAXExtrasMenuBarAttribute, from: appElement) else {
                continue
            }

            let elements = menuBarItems(in: extras)
            var keyOccurrences: [String: Int] = [:]
            for (menuIndex, element) in elements.enumerated() {
                guard let position: CGPoint = value(of: kAXPositionAttribute, from: element),
                      let size: CGSize = value(of: kAXSizeAttribute, from: element),
                      size.width > 1, size.height > 1 else {
                    continue
                }

                let appName = application.localizedName ?? "Menu Item"
                let bundleID = application.bundleIdentifier ?? "pid.\(application.processIdentifier)"
                let label = itemLabel(element: element, fallback: appName)
                let rawIdentifier: String? = value(of: kAXIdentifierAttribute, from: element)
                let accessibilityIdentifier = rawIdentifier.flatMap { rawValue -> String? in
                    let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.isEmpty ? nil : cleaned
                }
                let stableComponent = accessibilityIdentifier.map { "ax:\($0)" }
                    ?? "slot:\(menuIndex)"
                let occurrence = keyOccurrences[stableComponent, default: 0]
                keyOccurrences[stableComponent] = occurrence + 1
                let id = "\(bundleID)|\(stableComponent)|\(occurrence)"
                let icon = application.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
                icon.size = NSSize(width: 20, height: 20)
                let itemFrame = CGRect(origin: position, size: size)
                candidates.append(ScannedItemCandidate(
                    id: id,
                    applicationName: appName,
                    bundleIdentifier: bundleID,
                    label: label,
                    pid: application.processIdentifier,
                    menuIndex: menuIndex,
                    accessibilityIdentifier: accessibilityIdentifier,
                    frame: itemFrame,
                    icon: icon,
                    element: element
                ))
            }
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
            return lhs.frame.minX < rhs.frame.minX
        }
        let matchedWindows = matchWindows(
            to: sortedCandidates,
            availableWindows: availableWindows
        )

        let mappedCount = matchedWindows.compactMap { $0 }.count
        let unmatched = zip(sortedCandidates, matchedWindows).compactMap { candidate, matchedWindow in
            matchedWindow == nil ? candidate : nil
        }
        let diagnosticSignature = "\(mappedCount)/\(sortedCandidates.count)|\(unmatched.map(\.id).joined(separator: ","))"
        if diagnosticSignature != lastDiagnosticSignature {
            DiagnosticLogger.shared.log(
                "scan completed mapped=\(mappedCount) total=\(sortedCandidates.count) "
                    + "windowRecords=\(availableWindows.count) unmatched=\(unmatched.count)"
            )
            unmatched.forEach { candidate in
                DiagnosticLogger.shared.log(
                    "scan unmatched app=\(candidate.applicationName.debugDescription) "
                        + "item=\(candidate.label.debugDescription) id=\(candidate.id.debugDescription) "
                        + "axPID=\(candidate.pid) frame=\(candidate.frame.debugDescription)"
                )
            }
            lastDiagnosticSignature = diagnosticSignature
        }

        return zip(sortedCandidates, matchedWindows).compactMap { candidate, matchedWindow in
            guard let matchedWindow else { return nil }
            return MenuBarItem(
                id: candidate.id,
                applicationName: candidate.applicationName,
                bundleIdentifier: candidate.bundleIdentifier,
                label: candidate.label,
                pid: candidate.pid,
                menuIndex: candidate.menuIndex,
                accessibilityIdentifier: candidate.accessibilityIdentifier,
                windowID: matchedWindow.id,
                eventTargetPID: matchedWindow.ownerPID == 0 ? candidate.pid : matchedWindow.ownerPID,
                frame: candidate.frame,
                icon: candidate.icon,
                element: candidate.element
            )
        }
    }

    private func matchWindows(
        to candidates: [ScannedItemCandidate],
        availableWindows: [MenuBarWindowBridge.WindowRecord]
    ) -> [MenuBarWindowBridge.WindowRecord?] {
        MenuBarWindowMatcher.match(
            candidates: candidates.map { candidate in
                MenuBarWindowMatchCandidate(
                    frame: candidate.frame,
                    expectedTitles: Set(
                        [candidate.bundleIdentifier, candidate.accessibilityIdentifier]
                            .compactMap { $0 }
                    )
                )
            },
            availableWindows: availableWindows
        )
    }

    private func menuBarItems(in root: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 4 else { return }
            let role: String? = value(of: kAXRoleAttribute, from: element)
            if role == (kAXMenuBarItemRole as String) {
                found.append(element)
                return
            }
            let children: [AXUIElement] = value(of: kAXChildrenAttribute, from: element) ?? []
            children.forEach { walk($0, depth: depth + 1) }
        }

        walk(root, depth: 0)
        return found
    }

    private func itemLabel(element: AXUIElement, fallback: String) -> String {
        let attributes = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXIdentifierAttribute
        ]

        for attribute in attributes {
            if let text: String = value(of: attribute, from: element) {
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return fallback
    }

    private func value<T>(of attribute: String, from element: AXUIElement) -> T? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue) == .success,
              let rawValue else { return nil }

        if T.self == CGPoint.self {
            var point = CGPoint.zero
            guard CFGetTypeID(rawValue) == AXValueGetTypeID(),
                  AXValueGetType(rawValue as! AXValue) == .cgPoint,
                  AXValueGetValue(rawValue as! AXValue, .cgPoint, &point) else { return nil }
            return point as? T
        }

        if T.self == CGSize.self {
            var size = CGSize.zero
            guard CFGetTypeID(rawValue) == AXValueGetTypeID(),
                  AXValueGetType(rawValue as! AXValue) == .cgSize,
                  AXValueGetValue(rawValue as! AXValue, .cgSize, &size) else { return nil }
            return size as? T
        }

        return rawValue as? T
    }
}
