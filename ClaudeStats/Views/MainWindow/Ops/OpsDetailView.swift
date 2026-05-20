import SwiftUI

struct OpsDetailView: View {
    @Bindable var store: OpsStore
    let section: OpsSection
    private let horizontalInset: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { store.loadIfNeeded(section) }
        .onChange(of: section) { _, next in
            store.loadIfNeeded(next)
        }
        .alert("Ops", isPresented: errorPresented) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.lastError ?? "")
        }
        .confirmationDialog(
            store.pendingConfirmation?.title ?? "Confirm Action",
            isPresented: confirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Confirm", role: .destructive) {
                store.confirmPendingAction()
            }
            Button("Cancel", role: .cancel) {
                store.cancelPendingAction()
            }
        } message: {
            if let confirmation = store.pendingConfirmation {
                Text("\(confirmation.message)\n\n\(confirmation.commandSummary)")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OPS")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text(section.detailTitle)
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text(section.detailDescription)
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            if store.isLoading(section) || store.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .ports:
            OpsPortsView(store: store)
        case .processes:
            OpsProcessesView(store: store)
        case .brew:
            OpsToolScroll { OpsBrewView(store: store) }
        case .environment:
            OpsToolScroll { OpsEnvironmentView(store: store) }
        case .cleanup:
            OpsToolScroll { OpsCleanupView(store: store) }
        case .diagnostics:
            OpsToolScroll { OpsDiagnosticsView(store: store) }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.clearError() } }
        )
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { store.pendingConfirmation != nil },
            set: { if !$0 { store.cancelPendingAction() } }
        )
    }
}

struct OpsToolScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
    }
}

#if DEBUG
#Preview("Ops detail") {
    OpsDetailView(store: OpsStore(), section: .ports)
        .environment(AppEnvironment.preview())
        .frame(width: 980, height: 720)
        .background(Color.stxBackground)
}
#endif
