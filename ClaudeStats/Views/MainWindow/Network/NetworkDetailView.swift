import SwiftUI

struct NetworkDetailView: View {
    let section: NetworkSection
    @Environment(AppEnvironment.self) private var env
    private let horizontalInset: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NETWORK")
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
        .padding(.horizontal, horizontalInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .traffic:
            NetworkTrafficView(store: env.networkDebugger)
        case .setup:
            NetworkToolScroll {
                NetworkSetupView(store: env.networkDebugger)
            }
        case .certificates:
            NetworkToolScroll {
                NetworkCertificatesView(store: env.networkDebugger)
            }
        case .rules:
            NetworkToolScroll {
                NetworkRulesView()
            }
        }
    }
}

private struct NetworkToolScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 24) {
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

private extension NetworkSection {
    var detailTitle: String {
        switch self {
        case .traffic: "Network traffic"
        case .setup: "Proxy setup"
        case .certificates: "Certificates"
        case .rules: "Rules"
        }
    }

    var detailDescription: String {
        switch self {
        case .traffic:
            "Capture local HTTP traffic and inspect requests, responses, timing, and payloads."
        case .setup:
            "Configure the local proxy endpoint and system proxy handoff."
        case .certificates:
            "Manage the debugging root CA, trust status, and HTTPS inspection allowlist."
        case .rules:
            "Prepare rewrite, map-local, and breakpoint workflows for captured traffic."
        }
    }
}

#if DEBUG
#Preview("Network detail") {
    NetworkDetailView(section: .traffic)
        .environment(AppEnvironment.preview())
        .frame(width: 980, height: 720)
        .background(Color.stxBackground)
}
#endif
