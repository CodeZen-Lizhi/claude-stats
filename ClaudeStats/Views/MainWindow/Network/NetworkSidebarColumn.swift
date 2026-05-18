import SwiftUI

struct NetworkSidebarColumn: View {
    @Bindable var store: NetworkDebuggerStore
    @Binding var section: NetworkSection
    var onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(title: "Back to App",
                       symbol: "chevron.left",
                       isSelected: false,
                       action: onExit)

            captureControls
                .padding(.horizontal, 8)
                .padding(.top, 10)

            sectionHeader("NETWORK")

            ForEach(NetworkSection.allCases) { item in
                SidebarRow(title: item.title,
                           symbol: item.symbol,
                           isSelected: section == item) {
                    section = item
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusPill

            HStack(spacing: 8) {
                Button {
                    if store.captureStatus.isListening {
                        store.stopCapture()
                    } else {
                        store.startCapture()
                    }
                } label: {
                    Image(systemName: store.captureStatus.isListening ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.bordered)
                .help(store.captureStatus.isListening ? "Stop capture" : "Start capture")

                Button {
                    store.clearFlows()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(store.flows.isEmpty)
                .help("Clear traffic")
            }

            filterField

            VStack(alignment: .leading, spacing: 6) {
                Text("PROTOCOL")
                    .font(.sora(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
                    .padding(.leading, 2)

                LazyVGrid(columns: filterColumns, alignment: .leading, spacing: 6) {
                    filterButton("All", protocol: nil)
                    filterButton("HTTP", protocol: .http)
                    filterButton("HTTPS", protocol: .https)
                    filterButton("WebSocket", protocol: .webSocket)
                    filterButton("Tunnel", protocol: .tunnel)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.045))
        }
    }

    private var filterColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 76), spacing: 6, alignment: .leading),
            GridItem(.flexible(minimum: 76), spacing: 6, alignment: .leading)
        ]
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(store.captureStatus.isListening ? Color.green : Color.stxMuted.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(store.statusMessage)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(store.captureStatus.isListening ? .primary : Color.stxMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
            TextField("Filter", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
    }

    private func filterButton(_ title: String, protocol proto: NetworkFlowProtocol?) -> some View {
        let selected = store.selectedProtocol == proto
        return Button {
            store.selectedProtocol = proto
        } label: {
            Text(title)
                .font(.sora(10, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .primary : Color.stxMuted)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

#if DEBUG
#Preview("Network sidebar") {
    @Previewable @State var section: NetworkSection = .traffic
    @Previewable @State var store = NetworkDebuggerStore()
    return NetworkSidebarColumn(store: store, section: $section, onExit: {})
        .frame(width: 240, height: 620)
        .background(VisualEffectBackground())
}
#endif
