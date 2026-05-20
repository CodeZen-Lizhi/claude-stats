import AppKit
import SwiftUI

private enum SkillsPaneMetrics {
    static let sourceMinWidth: CGFloat = 220
    static let listMinWidth: CGFloat = 320
    static let detailMinWidth: CGFloat = 420
    static let secondaryMinWidth = listMinWidth + detailMinWidth

    static let outerConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: sourceMinWidth,
        secondaryMinimumPaneLength: secondaryMinWidth
    )
    static let detailConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: listMinWidth,
        secondaryMinimumPaneLength: detailMinWidth
    )
}

struct SkillsWorkspaceView: View {
    @Bindable var store: SkillsStore
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            SkillsHeader(store: store, refreshLocal: refreshLocal)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            StxRule()
            HoverableSplitView(
                axis: .vertical,
                primaryFraction: 0.22,
                configuration: SkillsPaneMetrics.outerConfiguration
            ) {
                SkillsSourceColumn(store: store)
                    .frame(minWidth: 0, idealWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            } secondary: {
                HoverableSplitView(
                    axis: .vertical,
                    primaryFraction: 0.42,
                    configuration: SkillsPaneMetrics.detailConfiguration
                ) {
                    SkillsListColumn(store: store)
                        .frame(minWidth: 0, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                } secondary: {
                    SkillsDetailPane(store: store)
                        .frame(minWidth: 0, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            await store.loadIfNeeded(sessions: env.store.sessions)
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            refreshLocal()
        }
        .onChange(of: store.selectedTab) { _, tab in
            if tab != .installed {
                Task { await store.refreshRemote() }
            }
        }
        .onChange(of: store.searchText) { _, _ in
            if store.selectedTab == .installed {
                store.syncLocalSelection()
            }
        }
        .onChange(of: store.selectedProviderID) { _, _ in store.syncLocalSelection() }
        .onChange(of: store.scopeFilter) { _, _ in store.syncLocalSelection() }
    }

    private func refreshLocal() {
        Task {
            await store.reloadLocal(sessions: env.store.sessions)
        }
    }
}

private struct SkillsHeader: View {
    @Bindable var store: SkillsStore
    let refreshLocal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skills")
                    .font(.sora(22, weight: .semibold))
                HStack(spacing: 8) {
                    Text("\(store.snapshot.summary.groupCount) skills")
                    Text(".")
                    Text("\(store.snapshot.summary.providerCount) providers")
                    if store.snapshot.summary.projectRootCount > 0 {
                        Text(".")
                        Text("\(store.snapshot.summary.projectRootCount) projects")
                    }
                    if let scannedAt = store.snapshot.scannedAt {
                        Text(".")
                        Text("Updated \(Format.relativeDate(scannedAt))")
                    }
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 12)

            if store.isScanning || store.isRemoteLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                if store.selectedTab == .installed {
                    refreshLocal()
                } else {
                    Task { await store.refreshRemote() }
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(store.isScanning || store.isRemoteLoading)
            .help("Refresh current Skills view")
        }
    }
}

private struct SkillsSourceColumn: View {
    @Bindable var store: SkillsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceTabs
                .padding(10)
            StxRule()
            filters
                .padding(12)
            if store.selectedTab != .installed {
                StxRule()
                apiKeyPanel
                    .padding(12)
            }
            Spacer(minLength: 0)
            summary
                .padding(12)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var workspaceTabs: some View {
        VStack(spacing: 6) {
            ForEach(SkillsWorkspaceTab.allCases) { tab in
                Button {
                    store.selectedTab = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(tab.title)
                            .font(.sora(12, weight: store.selectedTab == tab ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(store.selectedTab == tab ? Color.stxAccent : Color.stxMuted)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background {
                        if store.selectedTab == tab {
                            RoundedRectangle(cornerRadius: 7).fill(Color.stxAccent.opacity(0.13))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FILTERS")
                .font(.sora(9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.stxMuted)

            Picker("Provider", selection: providerBinding) {
                Text("All providers").tag("all")
                ForEach(store.snapshot.providers) { provider in
                    Label(provider.displayName, systemImage: provider.symbol).tag(provider.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Picker("Scope", selection: $store.scopeFilter) {
                ForEach(SkillScopeFilter.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(store.selectedTab != .installed)
        }
    }

    private var apiKeyPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: store.hasAPIKey ? "key.fill" : "key")
                    .foregroundStyle(store.hasAPIKey ? Color.stxAccent : Color.stxMuted)
                Text(store.hasAPIKey ? "API key saved" : "skills.sh API key")
                    .font(.sora(11, weight: .semibold))
            }

            SecureField("sk_live_...", text: $store.apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.sora(11))
                .onSubmit { store.saveAPIKey() }

            HStack(spacing: 8) {
                Button("Save") {
                    store.saveAPIKey()
                }
                .controlSize(.small)
                .disabled(store.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if store.hasAPIKey {
                    Button("Clear") {
                        store.deleteAPIKey()
                    }
                    .controlSize(.small)
                }
            }

            if !store.hasAPIKey {
                Text("Required for Discover and Curated.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkillsMiniMetric(value: "\(store.snapshot.summary.skillCount)", label: "copies")
            SkillsMiniMetric(value: "\(store.snapshot.summary.pluginSkillCount)", label: "plugin skills")
        }
        .font(.sora(10))
        .foregroundStyle(Color.stxMuted)
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { store.selectedProviderID ?? "all" },
            set: { store.selectedProviderID = $0 == "all" ? nil : $0 }
        )
    }
}

private struct SkillsListColumn: View {
    @Bindable var store: SkillsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
                .padding(10)
            StxRule()
            content
        }
        .background(Color.primary.opacity(0.025))
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(store.selectedTab.title)
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                if store.isScanning || store.isRemoteLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.stxMuted)
                TextField(searchPlaceholder, text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.sora(11))
                    .onSubmit {
                        if store.selectedTab == .discover {
                            Task { await store.searchOrLoadTrending() }
                        }
                    }
                if store.selectedTab == .discover {
                    Button {
                        Task { await store.searchOrLoadTrending() }
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .buttonStyle(.plain)
                    .help("Search skills.sh")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedTab {
        case .installed:
            installedList
        case .discover:
            remoteList(store.remoteResults)
        case .curated:
            curatedList
        }
    }

    private var installedList: some View {
        let groups = store.filteredLocalGroups
        return FadingScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if groups.isEmpty {
                    SkillsEmptyState(
                        symbol: "sparkles",
                        title: store.isScanning ? "Scanning..." : "No skills found",
                        message: "Refresh or adjust filters to inspect local SKILL.md directories."
                    )
                } else {
                    ForEach(groups) { group in
                        SkillsLocalRow(
                            group: group,
                            isSelected: store.selectedLocalGroupID == group.id
                        ) {
                            store.selectLocalGroup(group)
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    private func remoteList(_ skills: [RemoteSkillSummary]) -> some View {
        FadingScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if !store.hasAPIKey {
                    SkillsEmptyState(
                        symbol: "key",
                        title: "API key required",
                        message: "Save a skills.sh API key in the source column to browse the market."
                    )
                } else if let remoteError = store.remoteError {
                    SkillsEmptyState(symbol: "exclamationmark.triangle", title: "Could not load skills", message: remoteError)
                } else if skills.isEmpty {
                    SkillsEmptyState(symbol: "magnifyingglass", title: "No remote skills", message: "Search skills.sh or refresh trending results.")
                } else {
                    ForEach(skills) { skill in
                        SkillsRemoteRow(
                            skill: skill,
                            state: store.installState(for: skill),
                            isSelected: store.selectedRemoteSkillID == skill.id
                        ) {
                            store.selectRemoteSkill(skill)
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    private var curatedList: some View {
        FadingScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !store.hasAPIKey {
                    SkillsEmptyState(
                        symbol: "key",
                        title: "API key required",
                        message: "Save a skills.sh API key in the source column to browse curated skills."
                    )
                } else if let remoteError = store.remoteError {
                    SkillsEmptyState(symbol: "exclamationmark.triangle", title: "Could not load curated skills", message: remoteError)
                } else if store.curatedOwners.isEmpty {
                    SkillsEmptyState(symbol: "sparkles", title: "No curated skills", message: "Refresh to load official skills from skills.sh.")
                } else {
                    ForEach(store.curatedOwners) { owner in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(owner.owner)
                                    .font(.sora(11, weight: .semibold))
                                if let total = owner.totalInstalls {
                                    Text("\(total) installs")
                                        .font(.sora(9))
                                        .foregroundStyle(Color.stxMuted)
                                }
                            }
                            ForEach(owner.skills) { skill in
                                SkillsRemoteRow(
                                    skill: skill,
                                    state: store.installState(for: skill),
                                    isSelected: store.selectedRemoteSkillID == skill.id
                                ) {
                                    store.selectRemoteSkill(skill)
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    private var searchPlaceholder: String {
        switch store.selectedTab {
        case .installed: "Search local skills"
        case .discover: "Search skills.sh"
        case .curated: "Filter curated skills"
        }
    }
}

private struct SkillsDetailPane: View {
    @Bindable var store: SkillsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch store.selectedTab {
            case .installed:
                if let group = store.selectedLocalGroup {
                    SkillsLocalDetail(store: store, group: group)
                } else {
                    SkillsEmptyDetail()
                }
            case .discover, .curated:
                if let skill = store.selectedRemoteSkill {
                    SkillsRemoteDetail(store: store, skill: skill)
                        .task(id: skill.id) {
                            await store.loadRemoteDetail(id: skill.id)
                        }
                } else {
                    SkillsEmptyDetail()
                }
            }
        }
        .background(Color.primary.opacity(0.015))
    }
}

private struct SkillsLocalDetail: View {
    @Bindable var store: SkillsStore
    let group: LocalSkillGroup

    private var primary: LocalSkillItem? {
        group.primarySkill
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            StxRule()
            SkillsDetailTabs(selection: $store.selectedDetailTab)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            StxRule()
            detailBody
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(group.name)
                    .font(.sora(17, weight: .semibold))
                    .lineLimit(1)
                Text(group.description ?? "Local SKILL.md directory")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if let primary {
                ViewThatFits(in: .horizontal) {
                    actionButtons(primary, showLabels: true)
                    actionButtons(primary, showLabels: false)
                }
            }
        }
        .padding(14)
    }

    private func actionButtons(_ skill: LocalSkillItem, showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            SkillsToolbarButton("Copy Path", systemImage: "doc.on.doc", showLabel: showLabels) {
                SkillsClipboard.copy(skill.folderPath)
            }
            SkillsToolbarButton("Reveal", systemImage: "finder", showLabel: showLabels) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.skillMarkdownPath)])
            }
            SkillsToolbarButton("Open", systemImage: "arrow.up.right.square", showLabel: showLabels) {
                NSWorkspace.shared.open(URL(fileURLWithPath: skill.skillMarkdownPath))
            }
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        switch store.selectedDetailTab {
        case .overview:
            localOverview
        case .skill:
            if let primary {
                SkillMarkdownViewer(markdown: primary.skillMarkdown)
            }
        case .files:
            SkillFilesList(files: primary?.files ?? [])
        case .market:
            SkillsEmptyState(
                symbol: "bag",
                title: "Market comparison",
                message: "Select a skills.sh result in Discover or Curated to inspect remote metadata and audits."
            )
            .padding(16)
        }
    }

    private var localOverview: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SkillsMetricCard(title: "Copies", value: "\(group.installedCopyCount)")
                    SkillsMetricCard(title: "Files", value: "\(primary?.stats.fileCount ?? 0)")
                    SkillsMetricCard(title: "Tokens", value: "\(primary?.stats.tokenCount ?? 0)")
                }

                if let primary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Primary Copy")
                            .font(.sora(12, weight: .semibold))
                        SkillsFactRow("Provider", value: primary.providerName)
                        SkillsFactRow("Scope", value: primary.scope.displayName)
                        SkillsFactRow("Path", value: primary.displayPath)
                        if let creator = primary.frontmatter.creator {
                            SkillsFactRow("Creator", value: creator)
                        }
                        if let version = primary.frontmatter.version {
                            SkillsFactRow("Version", value: version)
                        }
                        if let plugin = primary.plugin {
                            SkillsFactRow("Plugin", value: plugin.displayName)
                        }
                    }
                    .mainWindowPanel(padding: 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Installed Copies")
                        .font(.sora(12, weight: .semibold))
                    ForEach(group.skills) { skill in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: skill.providerSymbol)
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(skill.providerName)
                                        .font(.sora(11, weight: .semibold))
                                    SkillsBadge(text: skill.scope.displayName, color: Color.stxMuted)
                                    if skill.isSymlink {
                                        SkillsBadge(text: "Symlink", color: Color.stxAccent)
                                    }
                                }
                                Text(skill.displayPath)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .mainWindowPanel(padding: 12)
            }
            .padding(14)
        }
    }
}

private struct SkillsRemoteDetail: View {
    @Bindable var store: SkillsStore
    let skill: RemoteSkillSummary

    private var bundle: SkillRemoteDetailBundle? {
        store.remoteDetails[skill.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            StxRule()
            SkillsDetailTabs(selection: $store.selectedDetailTab)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            StxRule()
            detailBody
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bag")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(skill.name)
                    .font(.sora(17, weight: .semibold))
                    .lineLimit(1)
                Text(skill.displaySource)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            ViewThatFits(in: .horizontal) {
                remoteActionButtons(showLabels: true)
                remoteActionButtons(showLabels: false)
            }
        }
        .padding(14)
    }

    private func remoteActionButtons(showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            SkillsToolbarButton("Copy Install", systemImage: "doc.on.doc", showLabel: showLabels, disabled: skill.installCommand == nil) {
                if let command = skill.installCommand {
                    SkillsClipboard.copy(command)
                }
            }
            SkillsToolbarButton("Open", systemImage: "arrow.up.right.square", showLabel: showLabels, disabled: remoteURL == nil) {
                if let remoteURL {
                    NSWorkspace.shared.open(remoteURL)
                }
            }
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        switch store.selectedDetailTab {
        case .overview:
            remoteOverview
        case .skill:
            if let markdown = bundle?.detail?.skillMarkdown {
                SkillMarkdownViewer(markdown: markdown)
            } else {
                SkillsLoadingState(message: store.isRemoteLoading ? "Loading SKILL.md..." : "No SKILL.md snapshot available.")
            }
        case .files:
            SkillFilesList(files: (bundle?.detail?.files ?? []).map {
                SkillFileEntry(path: $0.path, byteCount: Int64($0.contents?.utf8.count ?? 0), modifiedAt: nil)
            })
        case .market:
            auditView
        }
    }

    private var remoteOverview: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SkillsMetricCard(title: "Installs", value: skill.installs.map(String.init) ?? "-")
                    SkillsMetricCard(title: "Files", value: "\(bundle?.detail?.files.count ?? 0)")
                    SkillsMetricCard(title: "State", value: store.installState(for: skill).title)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Market Details")
                        .font(.sora(12, weight: .semibold))
                    SkillsFactRow("ID", value: skill.id)
                    if let source = skill.source {
                        SkillsFactRow("Source", value: source)
                    }
                    if let installURL = skill.installURL {
                        SkillsFactRow("Install URL", value: installURL)
                    }
                    if let hash = bundle?.detail?.hash {
                        SkillsFactRow("Hash", value: hash)
                    }
                    if let command = skill.installCommand {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Install Command")
                                .font(.sora(9, weight: .semibold))
                                .foregroundStyle(Color.stxMuted)
                            Text(command)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .mainWindowPanel(padding: 12)
            }
            .padding(14)
        }
    }

    private var auditView: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let audit = bundle?.audit, !audit.audits.isEmpty {
                    ForEach(audit.audits) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(entry.provider)
                                    .font(.sora(12, weight: .semibold))
                                SkillsBadge(text: entry.status.uppercased(), color: auditColor(entry.status))
                                if let risk = entry.riskLevel {
                                    SkillsBadge(text: risk, color: auditColor(entry.status))
                                }
                                Spacer(minLength: 0)
                            }
                            if let summary = entry.summary {
                                Text(summary)
                                    .font(.sora(11))
                                    .foregroundStyle(Color.stxMuted)
                            }
                            if let auditedAt = entry.auditedAt {
                                Text(Format.shortDate(auditedAt))
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                            }
                        }
                        .mainWindowPanel(padding: 12)
                    }
                } else {
                    SkillsEmptyState(
                        symbol: "checkmark.shield",
                        title: "No audit results",
                        message: "skills.sh returns audits after partner scans are available."
                    )
                }
            }
            .padding(14)
        }
    }

    private var remoteURL: URL? {
        if let url = skill.url.flatMap({ URL(string: $0) }) {
            return url
        }
        return skill.installURL.flatMap { URL(string: $0) }
    }

    private func auditColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "pass": Color.stxAccent
        case "warn": Color(red: 0.92, green: 0.58, blue: 0.16)
        case "fail": Color(red: 0.85, green: 0.22, blue: 0.18)
        default: Color.stxMuted
        }
    }
}

private struct SkillsLocalRow: View {
    let group: LocalSkillGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(group.name)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if group.installedCopyCount > 1 {
                        SkillsBadge(text: "\(group.installedCopyCount)", color: Color.stxAccent)
                    }
                }
                Text(group.description ?? "No description")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    ForEach(group.providers.prefix(3), id: \.self) { provider in
                        SkillsBadge(text: provider, color: Color.stxMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.stxAccent.opacity(0.11) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.32) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.name), \(group.installedCopyCount) installed copies")
    }
}

private struct SkillsRemoteRow: View {
    let skill: RemoteSkillSummary
    let state: SkillInstallState
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(skill.name)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    SkillsBadge(text: state.title, color: stateColor)
                }
                Text(skill.displaySource)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if let installs = skill.installs {
                        Label("\(installs)", systemImage: "arrow.down.circle")
                    }
                    if skill.isDuplicate {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                }
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.stxAccent.opacity(0.11) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.32) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(skill.name), \(state.title)")
    }

    private var stateColor: Color {
        switch state {
        case .installed: Color.stxAccent
        case .possiblyInstalled, .outOfDate: Color(red: 0.92, green: 0.58, blue: 0.16)
        case .notInstalled: Color.stxMuted
        }
    }
}

private struct SkillsDetailTabs: View {
    @Binding var selection: SkillsDetailTab

    var body: some View {
        FadingLine(fadeWidth: 24) {
            HStack(spacing: 14) {
                ForEach(SkillsDetailTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Text(tab.title)
                            .font(.sora(11, weight: selection == tab ? .semibold : .medium))
                            .foregroundStyle(selection == tab ? Color.stxAccent : Color.stxMuted)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
        }
    }
}

private struct SkillMarkdownViewer: View {
    let markdown: String

    var body: some View {
        ConfigurationTextEditor(
            text: .constant(markdown),
            fileKind: .markdown,
            isEditable: false,
            onCursorChange: { _, _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }
}

private struct SkillFilesList: View {
    let files: [SkillFileEntry]

    var body: some View {
        FadingScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if files.isEmpty {
                    SkillsEmptyState(symbol: "folder", title: "No file snapshot", message: "No supporting files are available for this skill.")
                } else {
                    ForEach(files) { file in
                        HStack(spacing: 9) {
                            Image(systemName: file.path == "SKILL.md" ? "doc.text" : "doc")
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 18)
                            Text(file.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            if let byteCount = file.byteCount {
                                Text(Format.bytes(Int(byteCount)))
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct SkillsFactRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(9, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.sora(10))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct SkillsMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SkillsBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.sora(8, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct SkillsMiniMetric: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.sora(10, weight: .semibold))
            Text(label)
                .font(.sora(10))
        }
    }
}

private struct SkillsToolbarButton: View {
    let title: String
    let systemImage: String
    let showLabel: Bool
    let disabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        showLabel: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.showLabel = showLabel
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if showLabel {
                Label(title, systemImage: systemImage)
            } else {
                Image(systemName: systemImage)
            }
        }
        .controlSize(.small)
        .help(title)
        .disabled(disabled)
    }
}

private struct SkillsEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Text(title)
                .font(.sora(13, weight: .semibold))
            Text(message)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillsLoadingState: View {
    let message: String

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SkillsEmptyDetail: View {
    var body: some View {
        SkillsEmptyState(
            symbol: "sparkles",
            title: "No skill selected",
            message: "Choose a local or market skill to inspect its SKILL.md, files, and metadata."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}

private enum SkillsClipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

#if DEBUG
#Preview("Skills") {
    SkillsWorkspaceView(store: AppEnvironment.preview().skills)
        .environment(AppEnvironment.preview())
        .frame(width: 1160, height: 760)
}
#endif
