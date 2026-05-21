import SwiftUI
import ClaudeStatsIconography

struct LinuxDoSidebarColumn: View {
    @Bindable var store: LinuxDoStore
    var signInEnabled = true
    var onExit: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: "chevron.left",
                isSelected: false,
                action: onExit
            )

            LinuxDoSourceColumn(store: store, signInEnabled: signInEnabled, onSignIn: onSignIn)
                .frame(maxHeight: .infinity)
        }
        .padding(.bottom, 10)
    }
}

struct LinuxDoSourceColumn: View {
    @Bindable var store: LinuxDoStore
    var signInEnabled = true
    var onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountSummary
                .padding(12)

            StxRule()

            AppScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    searchSection
                    feedSection
                    topSection
                    categoriesSection
                }
                .padding(12)
            }
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceHeader("Feeds")
            sourceButton(title: "Latest", symbol: "clock", feed: .latest)
            sourceButton(title: "Hot", symbol: "flame", feed: .hot)
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceHeader("Top")
            Picker("", selection: $store.topPeriod) {
                ForEach(LinuxDoTopPeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: store.topPeriod) { _, new in
                store.selectTopPeriod(new)
            }
            sourceButton(title: "Top \(store.topPeriod.displayName)", symbol: "chart.line.uptrend.xyaxis", feed: .top(store.topPeriod))
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourceHeader("Search")
            TextField("Search LinuxDo", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.sora(12))
                .onSubmit { store.submitSearch() }
                .onChange(of: store.searchText) { _, value in
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        store.scheduleSearch()
                    }
                }
            Button {
                store.submitSearch()
            } label: {
                FunctionalLabel("Search", systemSymbolName: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceHeader("Categories")
            if store.isLoadingCategories && store.categories.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.categories.prefix(28)) { category in
                    sourceButton(
                        title: category.name,
                        symbol: "folder",
                        feed: .category(id: category.id, name: category.name, slug: category.slug),
                        colorHex: category.colorHex
                    )
                }
            }
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FunctionalIconView(systemSymbolName: store.isAuthenticated ? "checkmark.seal" : "person")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(store.isAuthenticated ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.sora(12, weight: .medium))
                        .lineLimit(1)
                    Text(accountSubtitle)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if store.isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                } else if store.isAuthenticated {
                    Button("Sign Out") {
                        Task { await store.signOut() }
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        onSignIn()
                    } label: {
                        FunctionalLabel("Sign In", systemSymbolName: "person.crop.circle.badge.plus")
                    }
                    .controlSize(.small)
                    .disabled(!signInEnabled)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var accountTitle: String {
        if let user = store.currentUser {
            return "@\(user.username)"
        }
        if let username = store.authenticationStatus.username, !username.isEmpty {
            return "@\(username)"
        }
        return store.isAuthenticated ? "Signed in" : "Guest browsing"
    }

    private var accountSubtitle: String {
        store.isAuthenticated ? "\(store.authenticationDescription) active." : "Public feeds do not require sign-in."
    }

    private func sourceHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.sora(10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Color.stxMuted)
    }

    private func sourceButton(title: String, symbol: String, feed: LinuxDoFeed, colorHex: String? = nil) -> some View {
        Button {
            store.selectFeed(feed)
        } label: {
            HStack(spacing: 8) {
                if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex) ?? Color.stxMuted)
                        .frame(width: 8, height: 8)
                        .frame(width: 16)
                } else {
                    FunctionalIconView(systemSymbolName: symbol)
                        .frame(width: 16)
                        .foregroundStyle(store.selectedFeed == feed ? Color.stxAccent : Color.stxMuted)
                }
                Text(title)
                    .font(.sora(12, weight: store.selectedFeed == feed ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                if store.selectedFeed == feed {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.stxAccent.opacity(0.13))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = Int(cleaned, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
