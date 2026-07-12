import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    let collapse: () -> Void
    @State private var draggedID: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 32)

            Divider().frame(height: 24)

            content

            Divider().frame(height: 24)

            iconButton("arrow.clockwise", help: "刷新菜单栏项目") { model.scan() }
            iconButton("gearshape", help: "设置") { openSettings() }
            iconButton("chevron.up", help: "收起第二行") { collapse() }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var content: some View {
        if !model.isTrusted {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                Text("需要辅助功能权限")
                    .font(.system(size: 13, weight: .medium))
                Button("授权") { model.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
        } else if model.orderedFoldedItems().isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                Text("暂无折叠项目")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("选择") { openSettings() }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.orderedFoldedItems()) { item in
                        ShelfItemControl(
                            image: item.icon,
                            toolTip: "\(item.applicationName): \(item.label)",
                            action: { model.openApplication(item) }
                        )
                        .frame(width: 34, height: 34)
                        .onDrag {
                            draggedID = item.id
                            return NSItemProvider(object: item.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ShelfDropDelegate(
                            destinationID: item.id,
                            draggedID: $draggedID,
                            model: model
                        ))
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ShelfItemControl: NSViewRepresentable {
    let image: NSImage
    let toolTip: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> ShelfItemNSButton {
        let button = ShelfItemNSButton(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked)
        return button
    }

    func updateNSView(_ button: ShelfItemNSButton, context: Context) {
        context.coordinator.action = action
        button.image = image
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked() {
            action()
        }
    }
}

private final class ShelfItemNSButton: NSButton {
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.14 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

private struct ShelfDropDelegate: DropDelegate {
    let destinationID: String
    @Binding var draggedID: String?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != destinationID else { return }
        model.moveFoldedItem(from: draggedID, before: destinationID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BarFold")
                        .font(.system(size: 22, weight: .semibold))
                    Text("选择保留在菜单栏第一行的项目")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.revealDiagnosticLog()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("显示诊断日志")
                Button {
                    model.scan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
            }
            .padding(20)

            Divider()

            if !model.isTrusted {
                permissionView
            } else {
                List(model.items) { item in
                    itemRow(item)
                }
                .listStyle(.inset)
            }

            Divider()

            VStack(spacing: 12) {
                Toggle("登录时启动", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            .toggleStyle(.switch)
            .padding(20)
        }
        .frame(width: 480, height: 540)
        .alert("BarFold", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("好") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text("需要辅助功能权限")
                .font(.headline)
            Text("BarFold 通过辅助功能读取、重排并打开菜单栏项目。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack {
                Button("请求权限") { model.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
                Button("打开系统设置") { model.openAccessibilitySettings() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemRow(_ item: MenuBarItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.applicationName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Group {
                if item.isLockedInFirstRow {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help("macOS 固定在第一行，无法移动")
                        .accessibilityLabel("固定在第一行，无法移动")
                } else if model.pendingFoldIDs.contains(item.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Toggle("", isOn: Binding(
                        get: { !model.foldedIDs.contains(item.id) },
                        set: { model.setFolded(!$0, item: item) }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("显示在第一行")
                    .disabled(!model.pendingFoldIDs.isEmpty)
                }
            }
            .frame(width: 38)
        }
        .padding(.vertical, 5)
    }
}
