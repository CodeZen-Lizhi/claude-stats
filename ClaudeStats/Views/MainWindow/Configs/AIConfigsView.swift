import AppKit
import SwiftUI

struct AIConfigsView: View {
    @Environment(AppEnvironment.self) private var env
    @SceneStorage("mainWindow.configs.filter") private var filterRaw = AIConfigsFilter.all.rawValue
    @SceneStorage("mainWindow.configs.search") private var searchText = ""
    @SceneStorage("mainWindow.configs.projectID") private var selectedProjectIDRaw = ""
    @SceneStorage("mainWindow.configs.documentID") private var selectedDocumentIDRaw = ""

    private let workspaceMaxWidth: CGFloat = 980
    private let railColumnWidth: CGFloat = 78
    private let listColumnWidth: CGFloat = 330
    private let columnSpacing: CGFloat = 14

    private var filter: AIConfigsFilter {
        AIConfigsFilter(rawValue: filterRaw) ?? .all
    }

    var body: some View {
        let vm = env.aiConfigs
        let projects = vm.filteredProjects(filter: filter, query: searchText)
        let selectedProject = projects.first { $0.id == selectedProjectIDRaw }
        let documents = vm.documents(in: selectedProject, filter: filter, query: searchText)
        let selectedDocument = documents.first { $0.id == selectedDocumentIDRaw }

        CenteredPaneContainer(maxWidth: workspaceMaxWidth, topPadding: 36) {
            VStack(alignment: .leading, spacing: 18) {
                AIConfigsHeader(
                    summary: vm.snapshot.summary,
                    scannedAt: vm.snapshot.scannedAt,
                    isLoading: vm.isLoading,
                    refresh: refresh
                )

                WorkspaceColumnsLayout(
                    railWidth: railColumnWidth,
                    listWidth: listColumnWidth,
                    detailMinWidth: listColumnWidth,
                    spacing: columnSpacing
                ) {
                    AIConfigsFilterRail(selection: filterBinding)
                    AIConfigsProjectColumn(
                        projects: projects,
                        selectedProjectID: selectedProjectIDRaw,
                        searchText: searchBinding,
                        isLoading: vm.isLoading,
                        select: selectProject
                    )
                    AIConfigsDetailColumn(
                        project: selectedProject,
                        documents: documents,
                        selectedDocument: selectedDocument,
                        selectDocument: selectDocument,
                        refresh: refresh
                    )
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .task {
            await vm.loadIfNeeded(sessions: env.store.sessions)
            syncSelection()
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            Task {
                await env.aiConfigs.reload(sessions: env.store.sessions)
                syncSelection()
            }
        }
        .onChange(of: filterRaw) { _, _ in syncSelection() }
        .onChange(of: searchText) { _, _ in syncSelection() }
        .onChange(of: vm.snapshot) { _, _ in syncSelection() }
    }

    private var filterBinding: Binding<AIConfigsFilter> {
        Binding(
            get: { filter },
            set: { filterRaw = $0.rawValue }
        )
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { searchText = $0 }
        )
    }

    private func refresh() {
        Task {
            await env.aiConfigs.reload(sessions: env.store.sessions)
            syncSelection()
        }
    }

    private func selectProject(_ project: AIConfigProject) {
        selectedProjectIDRaw = project.id
        selectedDocumentIDRaw = env.aiConfigs
            .resolvedDocumentID(current: nil, projectID: project.id, filter: filter, query: searchText) ?? ""
    }

    private func selectDocument(_ document: AIConfigDocument) {
        selectedDocumentIDRaw = document.id
    }

    private func syncSelection() {
        let projectID = env.aiConfigs.resolvedProjectID(
            current: selectedProjectIDRaw.isEmpty ? nil : selectedProjectIDRaw,
            filter: filter,
            query: searchText
        )
        selectedProjectIDRaw = projectID ?? ""
        let documentID = env.aiConfigs.resolvedDocumentID(
            current: selectedDocumentIDRaw.isEmpty ? nil : selectedDocumentIDRaw,
            projectID: projectID,
            filter: filter,
            query: searchText
        )
        selectedDocumentIDRaw = documentID ?? ""
    }
}

private struct AIConfigsHeader: View {
    let summary: AIConfigSummary
    let scannedAt: Date?
    let isLoading: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Configs")
                    .font(.sora(28, weight: .semibold))
                HStack(spacing: 8) {
                    Text("\(summary.existingDocumentCount) files")
                    Text("·")
                    Text("\(summary.projectCount) projects")
                    if summary.diagnosticCount > 0 {
                        Text("·")
                        Text("\(summary.diagnosticCount) diagnostics")
                    }
                    if let scannedAt {
                        Text("·")
                        Text("Updated \(Format.relativeDate(scannedAt))")
                    }
                }
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(isLoading)
            .help("Refresh configs")
        }
    }
}

private struct AIConfigsFilterRail: View {
    @Binding var selection: AIConfigsFilter

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 10) {
                ForEach(AIConfigsFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        Image(systemName: filter.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(selection == filter ? Color.stxAccent : Color.stxMuted)
                            .frame(width: 54, height: 54)
                            .background {
                                if selection == filter {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.stxAccent.opacity(0.14))
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selection == filter ? Color.stxAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(filter.title)
                    .accessibilityLabel(filter.title)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
        .frame(width: 78, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

private struct AIConfigsProjectColumn: View {
    let projects: [AIConfigProject]
    let selectedProjectID: String
    @Binding var searchText: String
    let isLoading: Bool
    let select: (AIConfigProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Projects")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            searchField

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if projects.isEmpty {
                        Text("No configs")
                            .font(.sora(12))
                            .foregroundStyle(Color.stxMuted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(projects) { project in
                                AIConfigProjectRow(
                                    project: project,
                                    isSelected: selectedProjectID == project.id,
                                    select: { select(project) }
                                )
                                if project.id != projects.last?.id {
                                    StxRule().padding(.leading, 12)
                                }
                            }
                        }
                        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.automatic)
        }
        .frame(minWidth: 330, maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct AIConfigProjectRow: View {
    let project: AIConfigProject
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(project.name)
                            .font(.sora(12, weight: .semibold))
                            .lineLimit(1)
                        if project.summary.errorCount > 0 {
                            AIConfigsBadge(text: "\(project.summary.errorCount)", color: Color(red: 0.85, green: 0.22, blue: 0.18))
                        }
                    }
                    Text(detail)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        AIConfigsMiniStat(value: "\(project.summary.existingDocumentCount)", label: "files")
                        AIConfigsMiniStat(value: "\(project.summary.planStats.total)", label: "plans")
                        if project.summary.missingExpectedCount > 0 {
                            AIConfigsMiniStat(value: "\(project.summary.missingExpectedCount)", label: "missing")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7).fill(Color.stxAccent.opacity(0.11))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.name), \(project.summary.existingDocumentCount) config files")
    }

    private var iconName: String {
        switch project.kind {
        case .global: "globe"
        case .project: "folder"
        case .unassigned: "tray"
        }
    }

    private var detail: String {
        switch project.kind {
        case .global:
            "Global AI tool files"
        case .unassigned:
            "Plans without a clear project"
        case .project:
            project.path ?? "Project"
        }
    }
}

private struct AIConfigsDetailColumn: View {
    let project: AIConfigProject?
    let documents: [AIConfigDocument]
    let selectedDocument: AIConfigDocument?
    let selectDocument: (AIConfigDocument) -> Void
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let project {
                AIConfigProjectOverview(project: project)
                AIConfigDocumentList(
                    documents: documents,
                    selectedDocumentID: selectedDocument?.id,
                    select: selectDocument
                )
                AIConfigDocumentPreview(document: selectedDocument, refresh: refresh)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                    Text("No config selected")
                        .font(.sora(16, weight: .semibold))
                    Text("Refresh or adjust filters to inspect AI configuration files.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                .mainWindowPanel()
                .frame(minHeight: 520, alignment: .topLeading)
            }
        }
        .frame(minWidth: 330, maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
    }
}

private struct AIConfigProjectOverview: View {
    let project: AIConfigProject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.sora(17, weight: .semibold))
                        .lineLimit(1)
                    if let path = project.path {
                        Text(path)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(project.kind == .global ? "Global configuration scope" : "Unassigned plan scope")
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
                Spacer(minLength: 12)
                if let lastModified = project.lastModified {
                    AIConfigsBadge(text: Format.relativeDate(lastModified), color: Color.stxMuted)
                }
            }

            HStack(spacing: 10) {
                AIConfigsMetricCard(title: "Files", value: "\(project.summary.existingDocumentCount)")
                AIConfigsMetricCard(title: "Missing", value: "\(project.summary.missingExpectedCount)")
                AIConfigsMetricCard(title: "Plans", value: "\(project.summary.planStats.total)")
                AIConfigsMetricCard(title: "Issues", value: "\(project.summary.diagnosticCount)")
            }
        }
        .mainWindowPanel()
    }
}

private struct AIConfigDocumentList: View {
    let documents: [AIConfigDocument]
    let selectedDocumentID: String?
    let select: (AIConfigDocument) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Files")
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(documents.count)")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
            }

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if documents.isEmpty {
                        Text("No files in this filter.")
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(documents) { document in
                            AIConfigDocumentRow(
                                document: document,
                                isSelected: selectedDocumentID == document.id,
                                select: { select(document) }
                            )
                        }
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 190)
        }
        .mainWindowPanel()
    }
}

private struct AIConfigDocumentRow: View {
    let document: AIConfigDocument
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: document.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(document.title)
                            .font(.sora(11, weight: .semibold))
                            .lineLimit(1)
                        AIConfigsBadge(text: document.provider.shortName, color: document.provider.accentColor)
                        if !document.exists {
                            AIConfigsBadge(text: "Missing", color: Color.stxMuted)
                        }
                    }
                    Text(document.displayPath)
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.stxAccent.opacity(0.10) : Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.34) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(document.title), \(document.kind.singularDisplayName)")
    }

    private var iconColor: Color {
        if !document.exists { return Color.stxMuted }
        if document.diagnostics.contains(where: { $0.severity == .error }) {
            return Color(red: 0.85, green: 0.22, blue: 0.18)
        }
        if document.hasProblems {
            return Color(red: 0.92, green: 0.58, blue: 0.16)
        }
        return Color.stxAccent
    }
}

private struct AIConfigDocumentPreview: View {
    let document: AIConfigDocument?
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let document {
                previewToolbar(document)
                StxRule()
                if !document.diagnostics.isEmpty {
                    diagnostics(document.diagnostics)
                    StxRule()
                }
                previewBody(document)
                StxRule()
                previewStatus(document)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select a file")
                        .font(.sora(14, weight: .semibold))
                    Text("Choose a config file above to inspect its read-only preview and diagnostics.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private func previewToolbar(_ document: AIConfigDocument) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: document.kind.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(document.title)
                        .font(.sora(13, weight: .semibold))
                        .lineLimit(1)
                    AIConfigsBadge(text: document.fileKind.displayName, color: Color.stxMuted)
                    AIConfigsBadge(text: document.provider.shortName, color: document.provider.accentColor)
                    if !document.exists {
                        AIConfigsBadge(text: "Missing", color: Color.stxMuted)
                    }
                }
                Text(document.displayPath)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            ViewThatFits(in: .horizontal) {
                actionButtons(document, showLabels: true)
                actionButtons(document, showLabels: false)
            }
        }
        .padding(14)
    }

    private func actionButtons(_ document: AIConfigDocument, showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            toolbarButton("Open", systemImage: "arrow.up.right.square", showLabels: showLabels, disabled: !document.exists) {
                NSWorkspace.shared.open(URL(fileURLWithPath: document.path))
            }
            toolbarButton("Reveal", systemImage: "finder", showLabels: showLabels, disabled: !document.exists) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.path)])
            }
            toolbarButton("Refresh", systemImage: "arrow.clockwise", showLabels: showLabels, disabled: false, action: refresh)
        }
    }

    private func toolbarButton(
        _ title: String,
        systemImage: String,
        showLabels: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if showLabels {
                Label(title, systemImage: systemImage)
            } else {
                Image(systemName: systemImage)
            }
        }
        .help(title)
        .disabled(disabled)
    }

    private func diagnostics(_ diagnostics: [AIConfigDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(diagnostics) { diagnostic in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diagnostic.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(diagnostic.severity == .error ? Color(red: 0.85, green: 0.22, blue: 0.18) : Color(red: 0.92, green: 0.58, blue: 0.16))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.message)
                            .font(.sora(10, weight: .medium))
                            .lineLimit(2)
                        if let location = diagnostic.locationDisplay {
                            Text(location)
                                .font(.sora(9))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func previewBody(_ document: AIConfigDocument) -> some View {
        if !document.exists {
            Text("This expected file is not present.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        } else if document.isPreviewTruncated {
            Text("Preview skipped because this file is larger than \(Format.bytes(AIConfigScanner.previewByteLimit)).")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        } else if let content = document.contentPreview {
            ConfigurationTextEditor(
                text: .constant(content),
                fileKind: document.fileKind,
                isEditable: false,
                onCursorChange: { _, _ in }
            )
            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 360)
            .background(Color.primary.opacity(0.035))
        } else {
            Text("No preview available.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        }
    }

    private func previewStatus(_ document: AIConfigDocument) -> some View {
        HStack(spacing: 12) {
            if let fileSize = document.fileSize {
                Text(Format.bytes(Int(fileSize)))
            }
            if let modifiedAt = document.modifiedAt {
                Text(Format.shortDate(modifiedAt))
            }
            if document.fileKind == .markdown {
                Text("\(document.stats.headingCount) headings")
                Text("\(document.stats.uncheckedTaskCount) open tasks")
            }
            Spacer(minLength: 12)
            if document.diagnostics.isEmpty {
                Text(document.exists ? "Syntax OK" : "Missing")
                    .foregroundStyle(document.exists ? Color.stxAccent : Color.stxMuted)
            } else {
                Text("\(document.diagnostics.count) diagnostics")
            }
        }
        .font(.sora(10))
        .foregroundStyle(Color.stxMuted)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct AIConfigsMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(16, weight: .semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct AIConfigsMiniStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.sora(9, weight: .semibold))
            Text(label)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
    }
}

private struct AIConfigsBadge: View {
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

#if DEBUG
#Preview("Configs") {
    AIConfigsView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif
