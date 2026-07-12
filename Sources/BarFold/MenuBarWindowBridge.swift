import AppKit
import CoreGraphics

typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
private func CGSGetWindowCount(
    _ connection: CGSConnectionID,
    _ targetConnection: CGSConnectionID,
    _ count: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
private func CGSGetProcessMenuBarWindowList(
    _ connection: CGSConnectionID,
    _ targetConnection: CGSConnectionID,
    _ capacity: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ count: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
private func CGSGetScreenRectForWindow(
    _ connection: CGSConnectionID,
    _ windowID: CGWindowID,
    _ rect: inout CGRect
) -> CGError

enum MenuBarWindowBridge {
    struct WindowRecord: Sendable {
        let id: CGWindowID
        let ownerPID: pid_t
        let frame: CGRect
        let title: String?
    }

    static func windows() -> [WindowRecord] {
        let connection = CGSMainConnectionID()
        var capacity: Int32 = 0
        let countResult = CGSGetWindowCount(connection, 0, &capacity)
        guard countResult == .success, capacity > 0 else { return [] }

        var ids = [CGWindowID](repeating: 0, count: Int(capacity))
        var count: Int32 = 0
        let listResult = CGSGetProcessMenuBarWindowList(connection, 0, capacity, &ids, &count)
        guard listResult == .success else { return [] }
        return ids.prefix(Int(count)).compactMap(windowRecord)
    }

    static func frame(for windowID: CGWindowID) -> CGRect? {
        var frame = CGRect.zero
        guard CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &frame) == .success else {
            return nil
        }
        return frame
    }

    static func record(for windowID: CGWindowID) -> WindowRecord? {
        windowRecord(for: windowID)
    }

    static func matchingWindow(
        to itemFrame: CGRect,
        preferredWindowID: CGWindowID? = nil,
        excluding excludedWindowID: CGWindowID? = nil
    ) -> WindowRecord? {
        let candidates = windows().filter {
            $0.id != excludedWindowID && matchDistance($0.frame, itemFrame) <= 20
        }
        if let preferredWindowID,
           let preferred = candidates.first(where: { $0.id == preferredWindowID }) {
            return preferred
        }
        return candidates.min {
            matchDistance($0.frame, itemFrame) < matchDistance($1.frame, itemFrame)
        }
    }

    static func matchDistance(_ windowFrame: CGRect, _ itemFrame: CGRect) -> CGFloat {
        abs(windowFrame.midX - itemFrame.midX)
            + abs(windowFrame.midY - itemFrame.midY)
            + abs(windowFrame.width - itemFrame.width)
    }

    private static func windowRecord(for windowID: CGWindowID) -> WindowRecord? {
        var pointer = UnsafeRawPointer(bitPattern: Int(windowID))
        guard let frame = frame(for: windowID) else {
            return nil
        }
        let description: [CFString: CFTypeRef]? = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil)
            .flatMap { CGWindowListCreateDescriptionFromArray($0) as? [CFDictionary] }?
            .first as? [CFString: CFTypeRef]
        return WindowRecord(
            id: windowID,
            ownerPID: description?[kCGWindowOwnerPID] as? pid_t ?? 0,
            frame: frame,
            title: description?[kCGWindowName] as? String
        )
    }
}
