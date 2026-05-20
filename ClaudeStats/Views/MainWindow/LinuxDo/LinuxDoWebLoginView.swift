import AppKit
import SwiftUI
@preconcurrency import WebKit

struct LinuxDoWebLoginSheet: View {
    @Bindable var store: LinuxDoStore
    @Binding var isPresented: Bool
    @State private var status = "Sign in with Linux.do in the browser view."
    @State private var attemptedCookieSignature: String?
    @State private var isVerifying = false

    private let loginURL = URL(string: "https://linux.do/login")!

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LinuxDo Sign In")
                        .font(.sora(18, weight: .semibold))
                    Text(status)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                }
                Spacer()
                if isVerifying {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel") {
                    isPresented = false
                }
                .controlSize(.small)
            }
            .padding(14)

            StxRule()

            LinuxDoWebLoginView(url: loginURL) { cookies in
                handle(cookies: cookies)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 680)
    }

    @MainActor
    private func handle(cookies: [LinuxDoStoredCookie]) {
        let linuxCookies = cookies.filter(\.isLinuxDoCookie)
        let session = LinuxDoWebSession(cookies: linuxCookies)
        guard session.isAuthenticated,
              !isVerifying else {
            return
        }

        let signature = session.cookieHeader() ?? ""
        guard attemptedCookieSignature != signature else { return }
        attemptedCookieSignature = signature
        isVerifying = true
        status = "Verifying Linux.do browser session..."

        Task { @MainActor in
            let success = await store.signInWithWebSession(session)
            isVerifying = false
            if success {
                isPresented = false
            } else {
                attemptedCookieSignature = nil
                status = store.lastError ?? "Could not verify this Linux.do session yet."
            }
        }
    }
}

struct LinuxDoWebLoginView: NSViewRepresentable {
    let url: URL
    let onCookiesChanged: @MainActor @Sendable ([LinuxDoStoredCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesChanged: onCookiesChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, @unchecked Sendable {
        private let onCookiesChanged: @MainActor @Sendable ([LinuxDoStoredCookie]) -> Void

        init(onCookiesChanged: @escaping @MainActor @Sendable ([LinuxDoStoredCookie]) -> Void) {
            self.onCookiesChanged = onCookiesChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncCookies(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            syncCookies(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.targetFrame == nil, scheme == "http" || scheme == "https" {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
            } else {
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            }
        }

        private func syncCookies(from webView: WKWebView) {
            let callback = onCookiesChanged
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let stored = cookies
                    .map(LinuxDoStoredCookie.init(cookie:))
                    .filter(\.isLinuxDoCookie)
                Task { @MainActor in
                    callback(stored)
                }
            }
        }
    }
}
