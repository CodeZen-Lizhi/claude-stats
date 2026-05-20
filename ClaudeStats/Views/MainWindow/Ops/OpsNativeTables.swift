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
        tableView.headerView = OpsTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.rowHeight = OpsTableMetrics.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .fullWidth
        tableView.backgroundColor = .clear

        for column in OpsProcessTableColumn.allCases {
            tableView.addTableColumn(column.makeTableColumn())
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        AppScrollbars.configure(scrollView, axes: [.vertical, .horizontal])
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        AppScrollbars.configure(scrollView, axes: [.vertical, .horizontal])
        context.coordinator.tableView = tableView
        context.coordinator.applyHeaderLayout()
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
                let cell = processCell(in: tableView, for: column)
                cell.configure(title: item.displayName, badge: item.isDeveloperProcess ? "dev" : nil)
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

        func applyHeaderLayout() {
            OpsTableMetrics.applyHeaderLayout(to: tableView?.headerView)
        }

        private func textCell(in tableView: NSTableView, for column: OpsProcessTableColumn) -> OpsTextTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsTextTableCellView {
                return cell
            }
            let cell = OpsTextTableCellView()
            cell.identifier = column.identifier
            return cell
        }

        private func processCell(in tableView: NSTableView, for column: OpsProcessTableColumn) -> OpsProcessNameTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsProcessNameTableCellView {
                return cell
            }
            let cell = OpsProcessNameTableCellView()
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
        tableView.headerView = OpsTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.rowHeight = OpsTableMetrics.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .fullWidth
        tableView.backgroundColor = .clear

        for column in OpsPortTableColumn.allCases {
            tableView.addTableColumn(column.makeTableColumn())
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        AppScrollbars.configure(scrollView, axes: [.vertical, .horizontal])
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        AppScrollbars.configure(scrollView, axes: [.vertical, .horizontal])
        context.coordinator.tableView = tableView
        context.coordinator.applyHeaderLayout()
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
                let cell = processCell(in: tableView, for: column)
                cell.configure(title: item.processName, badge: nil)
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

        func applyHeaderLayout() {
            OpsTableMetrics.applyHeaderLayout(to: tableView?.headerView)
        }

        private func textCell(in tableView: NSTableView, for column: OpsPortTableColumn) -> OpsTextTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsTextTableCellView {
                return cell
            }
            let cell = OpsTextTableCellView()
            cell.identifier = column.identifier
            return cell
        }

        private func processCell(in tableView: NSTableView, for column: OpsPortTableColumn) -> OpsProcessNameTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? OpsProcessNameTableCellView {
                return cell
            }
            let cell = OpsProcessNameTableCellView()
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

    var alignment: NSTextAlignment {
        switch self {
        case .pid, .cpu, .memory: .right
        case .process, .user: .left
        }
    }

    @MainActor
    func makeTableColumn() -> NSTableColumn {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.headerCell = OpsTableHeaderCell(title: title, alignment: alignment)
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

    var alignment: NSTextAlignment {
        switch self {
        case .port, .pid: .right
        case .process, .address, .user: .left
        }
    }

    @MainActor
    func makeTableColumn() -> NSTableColumn {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.headerCell = OpsTableHeaderCell(title: title, alignment: alignment)
        column.width = width
        column.minWidth = minWidth
        column.maxWidth = maxWidth
        column.resizingMask = [.autoresizingMask, .userResizingMask]
        return column
    }
}

private enum OpsTableMetrics {
    static let headerHeight: CGFloat = 30
    static let headerHorizontalInset: CGFloat = 6
    static let headerBaselineOffset: CGFloat = -0.5
    static let rowHeight: CGFloat = 28

    @MainActor
    static func applyHeaderLayout(to headerView: NSTableHeaderView?) {
        guard let headerView else { return }
        guard abs(headerView.frame.height - headerHeight) > 0.5 else { return }
        headerView.frame.size.height = headerHeight
        headerView.needsDisplay = true
    }
}

private final class OpsTableHeaderView: NSTableHeaderView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: OpsTableMetrics.headerHeight))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        frame.size.height = OpsTableMetrics.headerHeight
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: OpsTableMetrics.headerHeight)
    }

    override func layout() {
        super.layout()
        OpsTableMetrics.applyHeaderLayout(to: self)
    }

    override func headerRect(ofColumn column: Int) -> NSRect {
        var rect = super.headerRect(ofColumn: column)
        rect.size.height = OpsTableMetrics.headerHeight
        return rect
    }
}

private final class OpsTableHeaderCell: NSTableHeaderCell {
    init(title: String, alignment: NSTextAlignment) {
        super.init(textCell: title)
        configure(alignment: alignment)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        configure(alignment: alignment)
    }

    private func configure(alignment: NSTextAlignment) {
        font = .opsFont(13, weight: .semibold)
        textColor = .labelColor
        self.alignment = alignment
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !stringValue.isEmpty else { return }
        let resolvedFont = font ?? .opsFont(13, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = lineBreakMode

        let attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont,
            .foregroundColor: textColor ?? NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
        let attributedTitle = NSAttributedString(string: stringValue, attributes: attributes)
        let textHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        var textRect = cellFrame.insetBy(dx: OpsTableMetrics.headerHorizontalInset, dy: 0)
        textRect.origin.y = max(
            cellFrame.minY + 2,
            floor(cellFrame.midY - textHeight / 2 + OpsTableMetrics.headerBaselineOffset)
        )
        textRect.size.height = textHeight
        attributedTitle.draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }
}

private final class OpsTextTableCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
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
    }
}

private final class OpsProcessNameTableCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private var titleBadgeGapConstraint: NSLayoutConstraint?
    private var badgeWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .opsFont(12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .opsFont(9, weight: .semibold)
        badgeLabel.textColor = .systemOrange
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 5
        badgeLabel.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor

        addSubview(titleLabel)
        addSubview(badgeLabel)

        let titleBadgeGapConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -6)
        let badgeWidthConstraint = badgeLabel.widthAnchor.constraint(equalToConstant: 28)
        self.titleBadgeGapConstraint = titleBadgeGapConstraint
        self.badgeWidthConstraint = badgeWidthConstraint

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleBadgeGapConstraint,

            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            badgeWidthConstraint,
            badgeLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(title: String, badge: String?) {
        titleLabel.stringValue = title
        if let badge {
            badgeLabel.stringValue = badge
            badgeLabel.isHidden = false
            titleBadgeGapConstraint?.constant = -6
            badgeWidthConstraint?.constant = 28
        } else {
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = true
            titleBadgeGapConstraint?.constant = 0
            badgeWidthConstraint?.constant = 0
        }
    }
}

private extension NSFont {
    static func opsFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: Theme.fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func opsMonospaced(_ size: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }
}
