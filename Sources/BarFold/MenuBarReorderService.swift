import AppKit
import ApplicationServices

enum BarFoldSyntheticEvent {
    static let userData: Int64 = 0x0042_4152_464F_4C44
}

final class MenuBarReorderService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.local.BarFold.reorder", qos: .userInitiated)

    func activate(item: MenuBarItem, completion: @escaping (Bool) -> Void) {
        queue.async {
            let startedAt = Date()
            let activationWindow = self.liveWindow(for: item, excluding: nil)
            let activationFrame = activationWindow?.frame
                ?? self.accessibilityFrame(of: item)
                ?? item.frame
            let activationWindowDescription = activationWindow?.id.description
                ?? item.windowID?.description
                ?? "nil"
            DiagnosticLogger.shared.log(
                "activation target item=\(item.label.debugDescription) "
                    + "window=\(activationWindowDescription) "
                    + "frame=\(self.describe(activationFrame))"
            )
            let pressResult: AXError
            if item.requiresDirectedActivation {
                pressResult = .actionUnsupported
                DiagnosticLogger.shared.log(
                    "activation AXPress skipped item=\(item.label.debugDescription) reason=known-incompatible"
                )
            } else {
                let appElement = AXUIElementCreateApplication(item.pid)
                AXUIElementSetMessagingTimeout(appElement, 0.35)
                let element = self.rediscoveredElement(for: item, appElement: appElement) ?? item.element
                AXUIElementSetMessagingTimeout(element, 0.35)
                pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
                DiagnosticLogger.shared.log(
                    "activation AXPress item=\(item.label.debugDescription) result=\(pressResult.rawValue)"
                )
            }
            if pressResult == .success {
                DiagnosticLogger.shared.log(
                    "activation succeeded item=\(item.label.debugDescription) method=AXPress "
                        + "elapsed=\(self.elapsed(since: startedAt))"
                )
                DispatchQueue.main.async { completion(true) }
                return
            }

            let liveWindow = activationWindow ?? self.liveWindow(for: item, excluding: nil)
            guard let windowID = liveWindow?.id ?? item.windowID else {
                DiagnosticLogger.shared.log(
                    "activation failed item=\(item.label.debugDescription) stage=window-resolution "
                        + "axResult=\(pressResult.rawValue)"
                )
                DispatchQueue.main.async { completion(false) }
                return
            }
            let targetPID = liveWindow.flatMap {
                $0.ownerPID == 0 ? nil : $0.ownerPID
            } ?? item.eventTargetPID
            let location = liveWindow?.frame.quartzCenter
                ?? MenuBarWindowBridge.frame(for: windowID)?.quartzCenter
                ?? item.frame.quartzCenter
            let context = "item=\(item.label.debugDescription) method=directed-click"
            let clicked = self.postDirectedClick(
                windowID: windowID,
                targetPID: targetPID,
                location: location,
                diagnosticContext: context
            )
            let resultName = clicked ? "succeeded" : "failed"
            DiagnosticLogger.shared.log(
                "activation \(resultName) \(context) window=\(windowID) "
                    + "targetPID=\(targetPID) elapsed=\(self.elapsed(since: startedAt))"
            )
            DispatchQueue.main.async { completion(clicked) }
        }
    }

    func move(
        item: MenuBarItem,
        intoHiddenSection hidden: Bool,
        separatorFrame: CGRect,
        separatorWindowID: CGWindowID?,
        completion: @escaping (Bool) -> Void
    ) {
        queue.async {
            let startedAt = Date()
            let destinationName = hidden ? "second-row" : "first-row"
            let cachedWindowDescription = item.windowID.map(String.init) ?? "nil"
            let separatorWindowDescription = separatorWindowID.map(String.init) ?? "nil"
            DiagnosticLogger.shared.log(
                "move requested item=\(item.label.debugDescription) id=\(item.id.debugDescription) "
                    + "destination=\(destinationName) cachedWindow=\(cachedWindowDescription) "
                    + "cachedPID=\(item.eventTargetPID) separatorWindow=\(separatorWindowDescription)"
            )

            for attempt in 0..<5 {
                let liveWindow = self.liveWindow(for: item, excluding: separatorWindowID)
                let itemWindowID = liveWindow?.id ?? item.windowID
                let itemTargetPID = liveWindow.flatMap {
                    $0.ownerPID == 0 ? nil : $0.ownerPID
                } ?? item.eventTargetPID
                let currentFrame = liveWindow?.frame ?? self.frame(of: item) ?? item.frame
                let currentSeparatorFrame = separatorWindowID
                    .flatMap(MenuBarWindowBridge.frame)
                    ?? separatorFrame
                let source = currentFrame.quartzCenter
                let isAlreadyPlaced = hidden
                    ? source.x < currentSeparatorFrame.midX
                    : source.x > currentSeparatorFrame.midX
                let context = "item=\(item.label.debugDescription) attempt=\(attempt + 1)/5"
                let liveWindowDescription = itemWindowID.map(String.init) ?? "nil"

                DiagnosticLogger.shared.log(
                    "move attempt \(context) liveWindow=\(liveWindowDescription) "
                        + "livePID=\(itemTargetPID) itemFrame=\(self.describe(currentFrame)) "
                        + "separatorFrame=\(self.describe(currentSeparatorFrame))"
                )

                if isAlreadyPlaced {
                    DiagnosticLogger.shared.log(
                        "move succeeded \(context) result=already-placed elapsed=\(self.elapsed(since: startedAt))"
                    )
                    DispatchQueue.main.async { completion(true) }
                    return
                }

                let moved: Bool
                if let itemWindowID, let separatorWindowID {
                    let destination = CGPoint(
                        x: hidden ? currentSeparatorFrame.minX : currentSeparatorFrame.maxX,
                        y: currentSeparatorFrame.midY
                    )
                    moved = self.postDirectedMove(
                        itemWindowID: itemWindowID,
                        separatorWindowID: separatorWindowID,
                        itemPID: itemTargetPID,
                        destination: destination,
                        diagnosticContext: context
                    )
                } else {
                    let horizontalOffset = max(currentFrame.width / 2 + 44 + CGFloat(attempt * 24), 64)
                    let destination = CGPoint(
                        x: hidden
                            ? currentSeparatorFrame.minX - horizontalOffset
                            : currentSeparatorFrame.maxX + horizontalOffset,
                        y: source.y
                    )
                    DiagnosticLogger.shared.log("move fallback \(context) method=screen-command-drag")
                    moved = self.postCommandDrag(
                        from: source,
                        to: destination,
                        diagnosticContext: context
                    )
                }

                guard moved else {
                    DiagnosticLogger.shared.log("move attempt failed \(context) stage=event-delivery retry=\(attempt < 4)")
                    if attempt < 4 {
                        if let itemWindowID {
                            let currentLocation = MenuBarWindowBridge.frame(for: itemWindowID)?.quartzCenter ?? source
                            let woke = self.wakeDirectedItem(
                                windowID: itemWindowID,
                                pid: itemTargetPID,
                                location: currentLocation,
                                diagnosticContext: context
                            )
                            DiagnosticLogger.shared.log("move retry preparation \(context) wake=\(woke)")
                        }
                        Thread.sleep(forTimeInterval: 0.08 + Double(attempt) * 0.04)
                    }
                    continue
                }

                if self.waitForPlacement(
                    of: item,
                    itemWindowID: itemWindowID,
                    hidden: hidden,
                    separatorWindowID: separatorWindowID,
                    fallbackSeparatorX: currentSeparatorFrame.midX
                ) {
                    DiagnosticLogger.shared.log(
                        "move succeeded \(context) result=placed elapsed=\(self.elapsed(since: startedAt))"
                    )
                    DispatchQueue.main.async { completion(true) }
                    return
                }

                DiagnosticLogger.shared.log("move attempt failed \(context) stage=placement-timeout retry=\(attempt < 4)")

                if attempt < 4, let itemWindowID {
                    let currentLocation = MenuBarWindowBridge.frame(for: itemWindowID)?.quartzCenter ?? source
                    _ = self.wakeDirectedItem(
                        windowID: itemWindowID,
                        pid: itemTargetPID,
                        location: currentLocation,
                        diagnosticContext: context
                    )
                    Thread.sleep(forTimeInterval: 0.08 + Double(attempt) * 0.04)
                }
            }
            DiagnosticLogger.shared.log(
                "move failed item=\(item.label.debugDescription) destination=\(destinationName) "
                    + "attempts=5 elapsed=\(self.elapsed(since: startedAt))"
            )
            DispatchQueue.main.async { completion(false) }
        }
    }

    private func postDirectedMove(
        itemWindowID: CGWindowID,
        separatorWindowID: CGWindowID,
        itemPID: pid_t,
        destination: CGPoint,
        diagnosticContext: String
    ) -> Bool {
        guard CGPreflightPostEventAccess() else {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=post-event-permission")
            return false
        }
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=event-source-creation")
            return false
        }

        if let suppressionSource = CGEventSource(stateID: .combinedSessionState) {
            let permittedEvents: CGEventFilterMask = [
                .permitLocalMouseEvents,
                .permitLocalKeyboardEvents,
                .permitSystemDefinedEvents,
            ]
            suppressionSource.setLocalEventsFilterDuringSuppressionState(
                permittedEvents,
                state: .eventSuppressionStateRemoteMouseDrag
            )
            suppressionSource.setLocalEventsFilterDuringSuppressionState(
                permittedEvents,
                state: .eventSuppressionStateSuppressionInterval
            )
            suppressionSource.localEventsSuppressionInterval = 0
        }

        guard let down = directedEvent(
            type: .leftMouseDown,
            location: CGPoint(x: 20_000, y: 20_000),
            windowID: itemWindowID,
            targetPID: itemPID,
            source: eventSource,
            command: true
        ) else {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=mouse-down-creation")
            return false
        }
        guard let up = directedEvent(
            type: .leftMouseUp,
            location: destination,
            windowID: separatorWindowID,
            targetPID: itemPID,
            source: eventSource,
            command: false
        ) else {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=mouse-up-creation")
            return false
        }

        let initialFrame = MenuBarWindowBridge.frame(for: itemWindowID)
        guard scrombleEvent(
            down,
            to: itemPID,
            stage: "mouse-down-delivery",
            diagnosticContext: diagnosticContext
        ) else { return false }
        if let initialFrame,
           !waitForFrameChange(windowID: itemWindowID, from: initialFrame, timeout: 0.18) {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=mouse-down-frame-change-timeout")
            _ = scrombleEvent(
                up,
                to: itemPID,
                stage: "cleanup-mouse-up-delivery",
                diagnosticContext: diagnosticContext
            )
            return false
        }
        return scrombleEvent(
            up,
            to: itemPID,
            stage: "mouse-up-delivery",
            diagnosticContext: diagnosticContext
        )
    }

    private func directedEvent(
        type: CGEventType,
        location: CGPoint,
        windowID: CGWindowID,
        targetPID: pid_t,
        source: CGEventSource,
        command: Bool
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ),
        let privateWindowField = CGEventField(rawValue: 0x33) else {
            return nil
        }

        event.flags = command ? .maskCommand : []
        let targetWindow = Int64(windowID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        event.setIntegerValueField(
            .eventSourceUserData,
            value: BarFoldSyntheticEvent.userData
        )
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: targetWindow)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: targetWindow)
        event.setIntegerValueField(privateWindowField, value: targetWindow)
        return event
    }

    private func postDirectedClick(
        windowID: CGWindowID,
        targetPID: pid_t,
        location: CGPoint,
        diagnosticContext: String
    ) -> Bool {
        guard CGPreflightPostEventAccess() else {
            DiagnosticLogger.shared.log("activation failed \(diagnosticContext) stage=post-event-permission")
            return false
        }
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            DiagnosticLogger.shared.log("activation failed \(diagnosticContext) stage=event-source-creation")
            return false
        }
        guard let down = directedEvent(
            type: .leftMouseDown,
            location: location,
            windowID: windowID,
            targetPID: targetPID,
            source: eventSource,
            command: false
        ) else {
            DiagnosticLogger.shared.log("activation failed \(diagnosticContext) stage=mouse-down-creation")
            return false
        }
        guard let up = directedEvent(
            type: .leftMouseUp,
            location: location,
            windowID: windowID,
            targetPID: targetPID,
            source: eventSource,
            command: false
        ) else {
            DiagnosticLogger.shared.log("activation failed \(diagnosticContext) stage=mouse-up-creation")
            return false
        }
        guard scrombleEvent(
            down,
            to: targetPID,
            stage: "activation-mouse-down-delivery",
            diagnosticContext: diagnosticContext
        ) else { return false }
        Thread.sleep(forTimeInterval: 0.03)
        return scrombleEvent(
            up,
            to: targetPID,
            stage: "activation-mouse-up-delivery",
            diagnosticContext: diagnosticContext
        )
    }

    private func wakeDirectedItem(
        windowID: CGWindowID,
        pid: pid_t,
        location: CGPoint,
        diagnosticContext: String
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = directedEvent(
                type: .leftMouseDown,
                location: location,
                windowID: windowID,
                targetPID: pid,
                source: source,
                command: true
              ),
              let up = directedEvent(
                type: .leftMouseUp,
                location: location,
                windowID: windowID,
                targetPID: pid,
                source: source,
                command: false
              ) else {
            return false
        }
        guard scrombleEvent(
            down,
            to: pid,
            stage: "wake-mouse-down-delivery",
            diagnosticContext: diagnosticContext
        ) else { return false }
        Thread.sleep(forTimeInterval: 0.02)
        return scrombleEvent(
            up,
            to: pid,
            stage: "wake-mouse-up-delivery",
            diagnosticContext: diagnosticContext
        )
    }

    private func waitForFrameChange(
        windowID: CGWindowID,
        from initialFrame: CGRect,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let currentFrame = MenuBarWindowBridge.frame(for: windowID),
               currentFrame != initialFrame {
                return true
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return false
    }

    private func scrombleEvent(
        _ event: CGEvent,
        to pid: pid_t,
        stage: String,
        diagnosticContext: String
    ) -> Bool {
        guard let nullEvent = CGEvent(source: nil) else {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=\(stage)-null-event-creation")
            return false
        }
        let context = DirectedEventContext(event: event, nullEvent: nullEvent, targetPID: pid)
        let retainedContext = Unmanaged.passRetained(context)
        defer { retainedContext.release() }
        let pointer = retainedContext.toOpaque()

        let nullMask = CGEventMask(1) << nullEvent.type.rawValue
        let eventMask = CGEventMask(1) << event.type.rawValue
        guard let pidTap = CGEvent.tapCreateForPid(
            pid: pid,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: nullMask,
            callback: directedPIDTapCallback,
            userInfo: pointer
        ) else {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=\(stage)-pid-tap-creation")
            return false
        }
        guard let sessionTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: directedSessionTapCallback,
            userInfo: pointer
        ) else {
            CFMachPortInvalidate(pidTap)
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=\(stage)-session-tap-creation")
            return false
        }
        guard let pidSource = CFMachPortCreateRunLoopSource(nil, pidTap, 0),
              let sessionSource = CFMachPortCreateRunLoopSource(nil, sessionTap, 0) else {
            CFMachPortInvalidate(pidTap)
            CFMachPortInvalidate(sessionTap)
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=\(stage)-run-loop-source-creation")
            return false
        }

        context.pidTap = pidTap
        context.sessionTap = sessionTap
        let runLoop = CFRunLoopGetCurrent()
        context.runLoop = runLoop
        CFRunLoopAddSource(runLoop, pidSource, .commonModes)
        CFRunLoopAddSource(runLoop, sessionSource, .commonModes)
        CGEvent.tapEnable(tap: pidTap, enable: true)
        CGEvent.tapEnable(tap: sessionTap, enable: true)

        nullEvent.postToPid(pid)
        let deadline = Date().addingTimeInterval(0.15)
        while !context.completed && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }

        CGEvent.tapEnable(tap: pidTap, enable: false)
        CGEvent.tapEnable(tap: sessionTap, enable: false)
        CFRunLoopRemoveSource(runLoop, pidSource, .commonModes)
        CFRunLoopRemoveSource(runLoop, sessionSource, .commonModes)
        CFMachPortInvalidate(pidTap)
        CFMachPortInvalidate(sessionTap)
        if !context.completed {
            DiagnosticLogger.shared.log("directed move failed \(diagnosticContext) stage=\(stage)-timeout")
        }
        return context.completed
    }

    private func waitForPlacement(
        of item: MenuBarItem,
        itemWindowID: CGWindowID?,
        hidden: Bool,
        separatorWindowID: CGWindowID?,
        fallbackSeparatorX: CGFloat
    ) -> Bool {
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 0.05)
            guard let currentFrame = itemWindowID.flatMap(MenuBarWindowBridge.frame) ?? frame(of: item) else {
                continue
            }
            let separatorX = separatorWindowID
                .flatMap(MenuBarWindowBridge.frame)?
                .midX ?? fallbackSeparatorX
            if hidden ? currentFrame.midX < separatorX : currentFrame.midX > separatorX {
                return true
            }
        }
        return false
    }

    private func liveWindow(
        for item: MenuBarItem,
        excluding separatorWindowID: CGWindowID?
    ) -> MenuBarWindowBridge.WindowRecord? {
        guard let itemFrame = accessibilityFrame(of: item) else {
            return item.windowID.flatMap(MenuBarWindowBridge.record)
        }
        return MenuBarWindowBridge.matchingWindow(
            to: itemFrame,
            preferredWindowID: item.windowID,
            excluding: separatorWindowID
        ) ?? item.windowID.flatMap(MenuBarWindowBridge.record)
    }

    private func postCommandDrag(
        from source: CGPoint,
        to destination: CGPoint,
        diagnosticContext: String
    ) -> Bool {
        guard CGPreflightPostEventAccess() else {
            DiagnosticLogger.shared.log("fallback drag failed \(diagnosticContext) stage=post-event-permission")
            return false
        }
        let originalCursorPosition = CGEvent(source: nil)?.location
        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let move = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .mouseMoved,
                mouseCursorPosition: source,
                mouseButton: .left
              ),
              let down = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .leftMouseDown,
                mouseCursorPosition: source,
                mouseButton: .left
              ) else {
            DiagnosticLogger.shared.log("fallback drag failed \(diagnosticContext) stage=initial-event-creation")
            return false
        }

        move.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
        down.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.12)

        let steps = 14
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: source.x + (destination.x - source.x) * progress,
                y: source.y + (destination.y - source.y) * progress
            )
            guard let drag = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                DiagnosticLogger.shared.log("fallback drag failed \(diagnosticContext) stage=drag-event-creation")
                return false
            }
            drag.flags = .maskCommand
            drag.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.018)
        }

        guard let up = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseUp,
            mouseCursorPosition: destination,
            mouseButton: .left
        ) else {
            DiagnosticLogger.shared.log("fallback drag failed \(diagnosticContext) stage=mouse-up-creation")
            return false
        }
        up.flags = .maskCommand
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        if let originalCursorPosition,
           let restore = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: originalCursorPosition,
            mouseButton: .left
           ) {
            restore.post(tap: .cghidEventTap)
        }
        return true
    }

    private func describe(_ frame: CGRect) -> String {
        String(
            format: "{x=%.1f,y=%.1f,w=%.1f,h=%.1f}",
            frame.origin.x,
            frame.origin.y,
            frame.width,
            frame.height
        )
    }

    private func elapsed(since date: Date) -> String {
        String(format: "%.3fs", Date().timeIntervalSince(date))
    }

    private func frame(of item: MenuBarItem) -> CGRect? {
        if let windowID = item.windowID,
           let frame = MenuBarWindowBridge.frame(for: windowID) {
            return frame
        }
        return accessibilityFrame(of: item)
    }

    private func accessibilityFrame(of item: MenuBarItem) -> CGRect? {
        let appElement = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(appElement, 1)
        let element = rediscoveredElement(for: item, appElement: appElement) ?? item.element
        guard let position: CGPoint = value(of: kAXPositionAttribute, from: element, type: .cgPoint),
              let size: CGSize = value(of: kAXSizeAttribute, from: element, type: .cgSize) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func rediscoveredElement(for item: MenuBarItem, appElement: AXUIElement) -> AXUIElement? {
        guard let extras: AXUIElement = attribute(kAXExtrasMenuBarAttribute, from: appElement) else {
            return nil
        }
        let elements = menuBarItems(in: extras)
        if let identifier = item.accessibilityIdentifier,
           let match = elements.first(where: {
               let candidate: String? = attribute(kAXIdentifierAttribute, from: $0)
               return candidate == identifier
           }) {
            return match
        }
        guard elements.indices.contains(item.menuIndex) else { return nil }
        return elements[item.menuIndex]
    }

    private func menuBarItems(in root: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 4 else { return }
            let role: String? = attribute(kAXRoleAttribute, from: element)
            if role == (kAXMenuBarItemRole as String) {
                found.append(element)
                return
            }
            let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
            children.forEach { walk($0, depth: depth + 1) }
        }

        walk(root, depth: 0)
        return found
    }

    private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }

    private func value<T>(of attribute: String, from element: AXUIElement, type: AXValueType) -> T? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID(),
              AXValueGetType(rawValue as! AXValue) == type else {
            return nil
        }

        if type == .cgPoint {
            var point = CGPoint.zero
            guard AXValueGetValue(rawValue as! AXValue, type, &point) else { return nil }
            return point as? T
        }

        var size = CGSize.zero
        guard AXValueGetValue(rawValue as! AXValue, type, &size) else { return nil }
        return size as? T
    }
}

private final class DirectedEventContext {
    let event: CGEvent
    let nullEvent: CGEvent
    let targetPID: pid_t
    let nullUserData: Int64
    let eventUserData: Int64
    var pidTap: CFMachPort?
    var sessionTap: CFMachPort?
    var runLoop: CFRunLoop?
    var completed = false

    init(event: CGEvent, nullEvent: CGEvent, targetPID: pid_t) {
        self.event = event
        self.nullEvent = nullEvent
        self.targetPID = targetPID
        nullUserData = Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(nullEvent)))
        eventUserData = event.getIntegerValueField(.eventSourceUserData)
        nullEvent.setIntegerValueField(.eventSourceUserData, value: nullUserData)
    }
}

private func directedPIDTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return nil }
    let context = Unmanaged<DirectedEventContext>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = context.pidTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return nil
    }
    guard event.getIntegerValueField(.eventSourceUserData) == context.nullUserData else {
        return nil
    }
    if let tap = context.pidTap {
        CGEvent.tapEnable(tap: tap, enable: false)
    }
    context.event.post(tap: .cgSessionEventTap)
    return nil
}

private func directedSessionTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return nil }
    let context = Unmanaged<DirectedEventContext>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = context.sessionTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return nil
    }
    guard event.getIntegerValueField(.eventSourceUserData) == context.eventUserData else {
        return nil
    }
    if let tap = context.sessionTap {
        CGEvent.tapEnable(tap: tap, enable: false)
    }
    context.event.postToPid(context.targetPID)
    context.completed = true
    if let runLoop = context.runLoop {
        CFRunLoopStop(runLoop)
    }
    return nil
}
