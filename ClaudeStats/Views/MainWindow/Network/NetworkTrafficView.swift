import AppKit
import SwiftUI

struct NetworkTrafficView: View {
    @Bindable var store: NetworkDebuggerStore
    @Bindable var preferences: Preferences

    var body: some View {
        GeometryReader { proxy in
            switch preferences.networkTrafficLayoutMode.resolved(
                width: Double(proxy.size.width),
                breakpoint: preferences.networkTrafficAutoBreakpoint
            ) {
            case .sideBySide:
                sideBySideLayout
            case .stacked:
                stackedLayout
            }
        }
    }

    private var sideBySideLayout: some View {
        HoverableSplitView(axis: .vertical, primaryFraction: 0.64) {
            trafficTable
                .frame(minWidth: 420, idealWidth: 720, maxWidth: .infinity, maxHeight: .infinity)
        } secondary: {
            inspector(.vertical)
                .frame(minWidth: 360, idealWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var stackedLayout: some View {
        HoverableSplitView(axis: .horizontal, primaryFraction: 0.46) {
            trafficTable
                .frame(minHeight: 220, maxHeight: .infinity)
        } secondary: {
            inspector(.horizontal)
                .frame(minHeight: 280, idealHeight: 340, maxHeight: .infinity)
        }
    }

    private var trafficTable: some View {
        NetworkTrafficTable(store: store)
        .frame(minHeight: 190, maxHeight: .infinity)
    }

    private func inspector(_ arrangement: NetworkInspectorPaneArrangement) -> some View {
        NetworkFlowInspector(store: store, arrangement: arrangement)
    }
}

private enum NetworkInspectorPaneArrangement {
    case vertical
    case horizontal
}

struct NetworkTrafficLayoutControls: View {
    @Bindable var preferences: Preferences
    @State private var showingAutoSettings = false

    var body: some View {
        HStack(spacing: 4) {
            layoutButton(.automatic) {
                preferences.networkTrafficLayoutMode = .automatic
                showingAutoSettings = true
            }
            .popover(isPresented: $showingAutoSettings, arrowEdge: .bottom) {
                NetworkTrafficAutoLayoutPopover(preferences: preferences)
                    .padding(14)
                    .frame(width: 260)
            }

            layoutButton(.stacked) {
                preferences.networkTrafficLayoutMode = .stacked
            }

            layoutButton(.sideBySide) {
                preferences.networkTrafficLayoutMode = .sideBySide
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.stxStroke.opacity(0.75), lineWidth: 1))
    }

    private func layoutButton(_ mode: NetworkTrafficLayoutMode, action: @escaping () -> Void) -> some View {
        let isSelected = preferences.networkTrafficLayoutMode == mode
        return Button(action: action) {
            Image(systemName: mode.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.stxAccent.opacity(0.14) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.stxAccent.opacity(0.35) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(mode.help)
        .accessibilityLabel(Text(mode.title))
    }
}

private struct NetworkTrafficAutoLayoutPopover: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("AUTO BREAKPOINT")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)

                Spacer(minLength: 8)

                Text("\(Int(preferences.networkTrafficAutoBreakpoint.rounded())) pt")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.primary.opacity(0.82))
            }

            Slider(
                value: $preferences.networkTrafficAutoBreakpoint,
                in: NetworkTrafficLayoutConstants.minimumAutoBreakpoint...NetworkTrafficLayoutConstants.maximumAutoBreakpoint,
                step: NetworkTrafficLayoutConstants.autoBreakpointStep
            )
            .controlSize(.small)

            HStack(spacing: 8) {
                Text("\(Int(NetworkTrafficLayoutConstants.minimumAutoBreakpoint))")
                Spacer()
                Text("\(Int(NetworkTrafficLayoutConstants.maximumAutoBreakpoint))")
            }
            .font(.sora(9).monospacedDigit())
            .foregroundStyle(Color.stxMuted.opacity(0.8))

            Button {
                preferences.resetNetworkTrafficAutoBreakpoint()
            } label: {
                Label("Reset to 900 pt", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}

private struct NetworkTrafficTable: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        ZStack {
            NetworkNativeTrafficTable(
                flows: store.filteredFlows,
                selectedFlowID: selectedFlowID
            )
            .background(Color.primary.opacity(0.025))

            if store.filteredFlows.isEmpty {
                NetworkInlineEmptyState(store.flows.isEmpty ? "Start capture to see traffic." : "No matching traffic.")
                    .padding(.top, 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private var selectedFlowID: Binding<UUID?> {
        Binding {
            store.selectedFlowID
        } set: { id in
            store.selectedFlowID = id
        }
    }
}

private struct NetworkNativeTrafficTable: NSViewRepresentable {
    var flows: [NetworkFlow]
    @Binding var selectedFlowID: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.headerView = NetworkTrafficHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .fullWidth

        for column in NetworkTrafficColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            let headerCell = NetworkTrafficHeaderCell(title: column.title, alignment: column.alignment)
            tableColumn.headerCell = headerCell
            tableColumn.width = column.idealWidth
            tableColumn.minWidth = column.minWidth
            tableColumn.maxWidth = column.maxWidth
            tableColumn.resizingMask = .userResizingMask
            tableView.addTableColumn(tableColumn)
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
        context.coordinator.applySelection()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        context.coordinator.tableView = tableView
        context.coordinator.applyHeaderLayout()
        tableView.reloadData()
        context.coordinator.applySelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NetworkNativeTrafficTable
        weak var tableView: NSTableView?
        private var isApplyingSelection = false

        init(parent: NetworkNativeTrafficTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.flows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.flows.count,
                  let column = NetworkTrafficColumn(identifier: tableColumn?.identifier) else {
                return nil
            }

            let cell = reusableCell(in: tableView, for: column)
            configure(cell, column: column, flow: parent.flows[row])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let tableView = notification.object as? NSTableView else {
                return
            }

            let row = tableView.selectedRow
            guard row >= 0, row < parent.flows.count else {
                parent.selectedFlowID = nil
                return
            }
            parent.selectedFlowID = parent.flows[row].id
        }

        func applySelection() {
            guard let tableView else { return }
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            guard let selectedFlowID = parent.selectedFlowID,
                  let row = parent.flows.firstIndex(where: { $0.id == selectedFlowID }) else {
                tableView.deselectAll(nil)
                return
            }

            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        func applyHeaderLayout() {
            guard let headerView = tableView?.headerView else { return }
            let targetHeight = NetworkTrafficTableMetrics.headerHeight
            guard abs(headerView.frame.height - targetHeight) > 0.5 else { return }
            headerView.frame.size.height = targetHeight
            headerView.needsDisplay = true
        }

        private func reusableCell(in tableView: NSTableView, for column: NetworkTrafficColumn) -> NSTableCellView {
            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView {
                return cell
            }

            let cell = NSTableCellView()
            cell.identifier = column.identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isSelectable = false
            textField.usesSingleLineMode = true
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: column.horizontalInset),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -column.horizontalInset),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            return cell
        }

        private func configure(_ cell: NSTableCellView, column: NetworkTrafficColumn, flow: NetworkFlow) {
            guard let textField = cell.textField else { return }
            textField.stringValue = column.value(for: flow)
            textField.alignment = column.alignment
            textField.font = column.font(for: flow)
            textField.textColor = column.textColor(for: flow)
            textField.lineBreakMode = column == .url ? .byTruncatingMiddle : .byTruncatingTail
        }
    }
}

private enum NetworkTrafficTableMetrics {
    static let headerHeight: CGFloat = 30
    static let headerHorizontalInset: CGFloat = 6
    static let headerBaselineOffset: CGFloat = -0.5
}

private final class NetworkTrafficHeaderView: NSTableHeaderView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: NetworkTrafficTableMetrics.headerHeight))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        frame.size.height = NetworkTrafficTableMetrics.headerHeight
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NetworkTrafficTableMetrics.headerHeight)
    }

    override func layout() {
        super.layout()
        if abs(frame.height - NetworkTrafficTableMetrics.headerHeight) > 0.5 {
            frame.size.height = NetworkTrafficTableMetrics.headerHeight
        }
    }
}

private final class NetworkTrafficHeaderCell: NSTableHeaderCell {
    init(title: String, alignment: NSTextAlignment) {
        super.init(textCell: title)
        configure(alignment: alignment)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        configure(alignment: alignment)
    }

    private func configure(alignment: NSTextAlignment) {
        font = .networkTableSora(size: 13, weight: .semibold)
        textColor = .labelColor
        self.alignment = alignment
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !stringValue.isEmpty else { return }
        let resolvedFont = font ?? .networkTableSora(size: 13, weight: .semibold)
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
        var textRect = cellFrame.insetBy(dx: NetworkTrafficTableMetrics.headerHorizontalInset, dy: 0)
        textRect.origin.y = floor(cellFrame.midY - textHeight / 2 + NetworkTrafficTableMetrics.headerBaselineOffset)
        textRect.size.height = textHeight
        attributedTitle.draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }
}

private enum NetworkTrafficColumn: String, CaseIterable {
    case state
    case number
    case url
    case client
    case method
    case status
    case time
    case duration
    case request
    case response
    case ssl
    case edited
    case tools

    init?(identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier, let column = Self(rawValue: identifier.rawValue) else { return nil }
        self = column
    }

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var title: String {
        switch self {
        case .state: ""
        case .number: "#"
        case .url: "URL"
        case .client: "Client"
        case .method: "Method"
        case .status: "Status"
        case .time: "Time"
        case .duration: "Duration"
        case .request: "Request"
        case .response: "Response"
        case .ssl: "SSL"
        case .edited: "Edited"
        case .tools: "Tools"
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .state: 20
        case .number: 42
        case .url: 260
        case .client: 120
        case .method: 72
        case .status: 70
        case .time: 102
        case .duration: 82
        case .request: 86
        case .response: 90
        case .ssl: 48
        case .edited: 54
        case .tools: 54
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .state: 20
        case .number: 50
        case .url: 430
        case .client: 155
        case .method: 86
        case .status: 82
        case .time: 116
        case .duration: 94
        case .request: 100
        case .response: 104
        case .ssl: 58
        case .edited: 64
        case .tools: 64
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .url: 920
        case .client: 260
        case .time: 150
        case .duration, .request, .response: 150
        case .method, .status: 120
        case .number: 70
        case .state: 20
        case .ssl: 78
        case .edited, .tools: 84
        }
    }

    var horizontalInset: CGFloat {
        switch self {
        case .state: 5
        default: 6
        }
    }

    var alignment: NSTextAlignment {
        switch self {
        case .url, .client:
            .left
        default:
            .center
        }
    }

    func value(for flow: NetworkFlow) -> String {
        switch self {
        case .state:
            "●"
        case .number:
            "\(flow.number)"
        case .url:
            flow.urlDisplay
        case .client:
            flow.clientName
        case .method:
            flow.request.method
        case .status:
            flow.statusDisplay
        case .time:
            flow.createdAt.formatted(date: .omitted, time: .standard)
        case .duration:
            duration(flow)
        case .request:
            bytes(flow.requestBytes)
        case .response:
            bytes(flow.responseBytes)
        case .ssl:
            flow.isSSLIntercepted ? "MITM" : "TLS"
        case .edited:
            flow.isEdited ? "Yes" : "-"
        case .tools:
            "..."
        }
    }

    func font(for flow: NetworkFlow) -> NSFont {
        switch self {
        case .method, .status:
            .networkTableSora(size: 11, weight: .semibold)
        case .state:
            .networkTableSora(size: 12, weight: .medium)
        default:
            .networkTableSora(size: 11, weight: .regular)
        }
    }

    func textColor(for flow: NetworkFlow) -> NSColor {
        switch self {
        case .state:
            switch flow.state {
            case .active: .systemYellow
            case .completed: .systemGreen
            case .failed: .systemRed
            }
        case .status:
            statusColor(for: flow)
        case .ssl, .edited, .tools:
            .secondaryLabelColor
        default:
            .labelColor
        }
    }

    private func statusColor(for flow: NetworkFlow) -> NSColor {
        guard let status = flow.response.statusCode else {
            return flow.state == .failed ? .systemRed : .systemYellow
        }
        if status < 300 { return .systemGreen }
        if status < 400 { return .systemYellow }
        return .systemRed
    }

    private func duration(_ flow: NetworkFlow) -> String {
        if flow.duration < 1 { return "\(Int((flow.duration * 1000).rounded())) ms" }
        return String(format: "%.2f s", flow.duration)
    }

    private func bytes(_ value: Int) -> String {
        guard value > 0 else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

private struct NetworkFlowInspector: View {
    @Bindable var store: NetworkDebuggerStore
    let arrangement: NetworkInspectorPaneArrangement

    var body: some View {
        Group {
            switch arrangement {
            case .vertical:
                HoverableSplitView(axis: .horizontal, primaryFraction: 0.48) {
                    payloadPane(.request)
                        .frame(minHeight: 170, idealHeight: 240, maxHeight: .infinity)
                } secondary: {
                    payloadPane(.response)
                        .frame(minHeight: 170, idealHeight: 260, maxHeight: .infinity)
                }
            case .horizontal:
                HoverableSplitView(axis: .vertical) {
                    payloadPane(.request)
                        .frame(minWidth: 260, idealWidth: 420, maxWidth: .infinity)
                } secondary: {
                    payloadPane(.response)
                        .frame(minWidth: 260, idealWidth: 420, maxWidth: .infinity)
                }
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private func payloadPane(_ side: NetworkInspectorSide) -> some View {
        NetworkPayloadPane(store: store, side: side)
    }
}

private struct NetworkPayloadPane: View {
    @Bindable var store: NetworkDebuggerStore
    let side: NetworkInspectorSide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader
            StxRule()
            paneBody
        }
        .background(Color.primary.opacity(0.025))
    }

    private var paneHeader: some View {
        HStack(spacing: 8) {
            Text(side.title.uppercased())
                .font(.sora(11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let flow = store.selectedFlow {
                headerBadge(flow)
                Text("#\(flow.number)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var paneBody: some View {
        if let flow = store.selectedFlow {
            FadingScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    payloadCard(flow)
                }
                .padding(14)
            }
        } else {
            NetworkInlineEmptyState("Start capture or select a request.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func payloadCard(_ flow: NetworkFlow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("PAYLOAD")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)

                Spacer(minLength: 8)

                ForEach(NetworkInspectorTab.allCases) { tab in
                    Button {
                        selectedTab.wrappedValue = tab
                    } label: {
                        Text(tab.title)
                            .font(.sora(10, weight: selectedTab.wrappedValue == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab.wrappedValue == tab ? Color.stxAccent : Color.stxMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            StxRule()

            Text(content(for: flow))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.84))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)

            if payloadBody(for: flow).isTruncated {
                StxRule()
                Text("Body truncated at capture limit.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .padding(12)
            }
        }
        .networkInspectorCard()
    }

    private var selectedTab: Binding<NetworkInspectorTab> {
        Binding {
            side == .request ? store.selectedRequestTab : store.selectedResponseTab
        } set: { tab in
            if side == .request {
                store.selectedRequestTab = tab
            } else {
                store.selectedResponseTab = tab
            }
        }
    }

    @ViewBuilder
    private func headerBadge(_ flow: NetworkFlow) -> some View {
        switch side {
        case .request:
            methodBadge(flow.request.method)
        case .response:
            statusBadge(flow)
        }
    }

    private func methodBadge(_ method: String) -> some View {
        Text(method)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func statusBadge(_ flow: NetworkFlow) -> some View {
        Text(flow.statusDisplay)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(statusColor(flow))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(flow).opacity(0.14), in: Capsule())
    }

    private func content(for flow: NetworkFlow) -> String {
        switch selectedTab.wrappedValue {
        case .header:
            return headers(for: flow).map { "\($0.name): \($0.value)" }.joined(separator: "\n").nonEmpty(or: "No headers")
        case .query:
            return queryString(for: flow).nonEmpty(or: "No query parameters")
        case .body:
            return payloadBody(for: flow).text.nonEmpty(or: "No body")
        case .raw:
            return raw(for: flow)
        case .json:
            return prettyJSON(payloadBody(for: flow).text).nonEmpty(or: "No JSON body")
        }
    }

    private func headers(for flow: NetworkFlow) -> [NetworkHeaderPair] {
        side == .request ? flow.request.headers : flow.response.headers
    }

    private func payloadBody(for flow: NetworkFlow) -> NetworkBody {
        side == .request ? flow.request.body : flow.response.body
    }

    private func queryString(for flow: NetworkFlow) -> String {
        guard side == .request,
              let components = URLComponents(string: flow.request.url),
              let items = components.queryItems,
              !items.isEmpty else { return "" }
        return items.map { "\($0.name): \($0.value ?? "")" }.joined(separator: "\n")
    }

    private func raw(for flow: NetworkFlow) -> String {
        if side == .request {
            let head = "\(flow.request.method) \(flow.request.url) \(flow.request.httpVersion)"
            return ([head] + flow.request.headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
                + "\n\n"
                + flow.request.body.text
        }
        let head = "HTTP \(flow.response.statusCode.map(String.init) ?? "-") \(flow.response.reason)"
        return ([head] + flow.response.headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
            + "\n\n"
            + flow.response.body.text
    }

    private func statusColor(_ flow: NetworkFlow) -> Color {
        guard let status = flow.response.statusCode else {
            return flow.state == .failed ? .red : .yellow
        }
        if status < 300 { return .green }
        if status < 400 { return .yellow }
        return .red
    }

    private func duration(_ flow: NetworkFlow) -> String {
        if flow.duration < 1 { return "\(Int((flow.duration * 1000).rounded())) ms" }
        return String(format: "%.2f s", flow.duration)
    }

    private func bytes(_ value: Int) -> String {
        guard value > 0 else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func prettyJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let output = String(data: pretty, encoding: .utf8) else {
            return ""
        }
        return output
    }
}

private struct NetworkInlineEmptyState: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.sora(10))
            .foregroundStyle(Color.stxMuted.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
    }
}

private extension View {
    func networkInspectorCard() -> some View {
        self
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

private extension NSFont {
    static func networkTableSora(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: Theme.fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
