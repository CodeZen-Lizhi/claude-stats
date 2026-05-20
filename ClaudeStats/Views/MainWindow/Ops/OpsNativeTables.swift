import AppKit
import SwiftUI

struct OpsNativeProcessTable: NSViewRepresentable {
    var rows: [OpsProcessTableRow]
    var rowsVersion: Int
    @Binding var selectedID: Int32?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.rowHeight = 46
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .fullWidth
        tableView.backgroundColor = .clear

        for column in OpsProcessTableColumn.allCases {
            tableView.addTableColumn(column.makeTableColumn())
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.tableView = tableView
        if context.coordinator.rowsVersion != rowsVersion {
            context.coordinator.rowsVersion = rowsVersion
            tableView.reloadData()
        }
        context.coordinator.applySelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: OpsNativeProcessTable
        var rowsVersion = -1
        weak var tableView: NSTableView?
        private var isApplyingSelection = false

        init(parent: OpsNativeProcessTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count,
                  let column = OpsProcessTableColumn(identifier: tableColumn?.identifier) else {
                return nil
            }

            let item = parent.rows[row]
            switch column {
            case .pid:
                let cell = textCell(in: tableView, for: column)
                cell.configure(
                    item.pidText,
                    alignment: .right,
                    color: item.protectionReason == nil ? .secondaryLabelColor : .systemOrange,
                    font: .opsMonospaced(11)
                )
                return cell
            case .process:
                let cell = twoLineCell(in: tableView, for: column)
                cell.configure(title: item.displayName, detail: item.commandLine, badge: item.isDeveloperProcess ? "dev" : nil)
                return cell
            case .cpu:
                let cell = textCell(in: tableView, for: column)
                cell.configure(item.cpuText, alignment: .right, font: .opsMonospaced(11))
                return cell
            case .memory:
                let cell = textCell(in: tableView, for: column)
                cell.configure(item.memoryText, alignment: .right, color: .secondaryLabelColor, font: .opsMonospaced(11))
                return cell
            case .user:
                let cell = textCell(in: tableView, for: column)
                cell.configure(item.user, alignment: .left, color: .secondaryLabelColor, font: .opsFont(11))
                return cell
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let tableView = notification.object as? NSTableView else {
                return
            }

            let row = tableView.selectedRow
            guard row >= 0, row < parent.rows.count else {
                parent.selectedID = nil
                return
            }
            parent.selectedID = parent.rows[row].id
        }

        func applySelection() {
            guard let tableView else { return }
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            guard let selectedID = parent.selectedID,
                  let row = parent.rows.firstIndex(where: { $0.id == selectedID }) else {
                tableView.deselectAll(nil)
                return
            }
            guard tableView.selectedRow != row else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        private func textCell(in tableView: NSTableView, for column: OpsProcessTableColumn) -> OpsTextTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsTextTableCellView {
                return cell
            }
            let cell = OpsTextTableCellView()
            cell.identifier = column.identifier
            return cell
        }

        private func twoLineCell(in tableView: NSTableView, for column: OpsProcessTableColumn) -> OpsTwoLineTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsTwoLineTableCellView {
                return cell
            }
            let cell = OpsTwoLineTableCellView()
            cell.identifier = column.identifier
            return cell
        }
    }
}

struct OpsNativePortTable: NSViewRepresentable {
    var rows: [OpsPortTableRow]
    var rowsVersion: Int
    @Binding var selectedID: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.rowHeight = 38
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .fullWidth
        tableView.backgroundColor = .clear

        for column in OpsPortTableColumn.allCases {
            tableView.addTableColumn(column.makeTableColumn())
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.tableView = tableView
        if context.coordinator.rowsVersion != rowsVersion {
            context.coordinator.rowsVersion = rowsVersion
            tableView.reloadData()
        }
        context.coordinator.applySelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: OpsNativePortTable
        var rowsVersion = -1
        weak var tableView: NSTableView?
        private var isApplyingSelection = false

        init(parent: OpsNativePortTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count,
                  let column = OpsPortTableColumn(identifier: tableColumn?.identifier) else {
                return nil
            }

            let item = parent.rows[row]
            switch column {
            case .port:
                let cell = textCell(in: tableView, for: column)
                cell.configure(item.portText, alignment: .right, font: .opsMonospaced(11))
                return cell
            case .process:
                let cell = twoLineCell(in: tableView, for: column)
                cell.configure(title: item.processName, detail: item.commandLine, badge: nil)
                return cell
            case .address:
                let cell = textCell(in: tableView, for: column)
                cell.configure(item.displayAddress, alignment: .left, color: .secondaryLabelColor, font: .opsFont(11))
                return cell
            case .pid:
                let cell = textCell(in: tableView, for: column)
                cell.configure(
                    item.pidText,
                    alignment: .right,
                    color: item.protectionReason == nil ? .secondaryLabelColor : .systemOrange,
                    font: .opsMonospaced(11)
                )
                return cell
            case .user:
                let cell = textCell(in: tableView, for: column)
                cell.configure(item.user, alignment: .left, color: .secondaryLabelColor, font: .opsFont(11))
                return cell
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let tableView = notification.object as? NSTableView else {
                return
            }

            let row = tableView.selectedRow
            guard row >= 0, row < parent.rows.count else {
                parent.selectedID = nil
                return
            }
            parent.selectedID = parent.rows[row].id
        }

        func applySelection() {
            guard let tableView else { return }
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            guard let selectedID = parent.selectedID,
                  let row = parent.rows.firstIndex(where: { $0.id == selectedID }) else {
                tableView.deselectAll(nil)
                return
            }
            guard tableView.selectedRow != row else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        private func textCell(in tableView: NSTableView, for column: OpsPortTableColumn) -> OpsTextTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsTextTableCellView {
                return cell
            }
            let cell = OpsTextTableCellView()
            cell.identifier = column.identifier
            return cell
        }

        private func twoLineCell(in tableView: NSTableView, for column: OpsPortTableColumn) -> OpsTwoLineTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsTwoLineTableCellView {
                return cell
            }
            let cell = OpsTwoLineTableCellView()
            cell.identifier = column.identifier
            return cell
        }
    }
}

private enum OpsProcessTableColumn: String, CaseIterable {
    case pid
    case process
    case cpu
    case memory
    case user

    init?(identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier else { return nil }
        self.init(rawValue: identifier.rawValue)
    }

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var title: String {
        switch self {
        case .pid: "PID"
        case .process: "Process"
        case .cpu: "CPU"
        case .memory: "MEM"
        case .user: "User"
        }
    }

    var width: CGFloat {
        switch self {
        case .pid: 72
        case .process: 320
        case .cpu: 70
        case .memory: 70
        case .user: 120
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .pid: 58
        case .process: 180
        case .cpu, .memory: 58
        case .user: 80
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .process: 1_000
        case .user: 220
        default: width
        }
    }

    @MainActor
    func makeTableColumn() -> NSTableColumn {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = minWidth
        column.maxWidth = maxWidth
        column.resizingMask = self == .process ? .autoresizingMask : .userResizingMask
        return column
    }
}

private enum OpsPortTableColumn: String, CaseIterable {
    case port
    case process
    case address
    case pid
    case user

    init?(identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier else { return nil }
        self.init(rawValue: identifier.rawValue)
    }

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var title: String {
        switch self {
        case .port: "Port"
        case .process: "Process"
        case .address: "Address"
        case .pid: "PID"
        case .user: "User"
        }
    }

    var width: CGFloat {
        switch self {
        case .port: 78
        case .process: 260
        case .address: 180
        case .pid: 72
        case .user: 120
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .port, .pid: 58
        case .process: 160
        case .address: 120
        case .user: 80
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .process, .address: 800
        case .user: 220
        default: width
        }
    }

    @MainActor
    func makeTableColumn() -> NSTableColumn {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = minWidth
        column.maxWidth = maxWidth
        column.resizingMask = [.autoresizingMask, .userResizingMask]
        return column
    }
}

private final class OpsTextTableCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private var insets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.lineBreakMode = .byTruncatingTail
        label.usesSingleLineMode = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(
            x: insets.left,
            y: 0,
            width: max(bounds.width - insets.left - insets.right, 0),
            height: bounds.height
        )
    }

    func configure(
        _ text: String,
        alignment: NSTextAlignment,
        color: NSColor = .labelColor,
        font: NSFont = .opsFont(11)
    ) {
        label.stringValue = text
        label.alignment = alignment
        label.textColor = color
        label.font = font
        needsLayout = true
    }
}

private final class OpsTwoLineTableCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .opsFont(12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true

        detailLabel.font = .opsFont(10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.usesSingleLineMode = true

        badgeLabel.font = .opsFont(9, weight: .semibold)
        badgeLabel.textColor = .systemOrange
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 5
        badgeLabel.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor

        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(badgeLabel)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        let left: CGFloat = 8
        let right: CGFloat = 8
        let availableWidth = max(bounds.width - left - right, 0)
        let badgeWidth = badgeLabel.isHidden ? 0 : min(max(badgeLabel.intrinsicContentSize.width + 10, 28), 42)
        let badgeGap: CGFloat = badgeLabel.isHidden ? 0 : 6
        let titleWidth = max(availableWidth - badgeWidth - badgeGap, 0)

        titleLabel.frame = NSRect(x: left, y: bounds.height - 22, width: titleWidth, height: 16)
        if !badgeLabel.isHidden {
            badgeLabel.frame = NSRect(x: left + titleWidth + badgeGap, y: bounds.height - 22, width: badgeWidth, height: 16)
        }
        detailLabel.frame = NSRect(x: left, y: 6, width: availableWidth, height: 14)
    }

    func configure(title: String, detail: String, badge: String?) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        if let badge {
            badgeLabel.stringValue = badge
            badgeLabel.isHidden = false
        } else {
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = true
        }
        needsLayout = true
    }
}

private extension NSFont {
    static func opsFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: "Sora", size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func opsMonospaced(_ size: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }
}
