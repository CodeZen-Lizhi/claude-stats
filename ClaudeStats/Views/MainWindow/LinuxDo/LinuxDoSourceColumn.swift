import SwiftUI

struct LinuxDoSourceColumn: View {
    @Bindable var store: LinuxDoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    feedSection
                    topSection
                    searchSection
                    categoriesSection
                }
                .padding(12)
            }

            StxRule()
            accountSummary
                .padding(12)
        }
        .background(Color.primary.opacity(0.025))
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
                Label("Search", systemImage: "magnifyingglass")
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
        VStack(alignment: .leading, spacing: 6) {
            if let user = store.currentUser {
                Label("@\(user.username)", systemImage: "person.crop.circle")
                    .font(.sora(12, weight: .medium))
            } else {
                Label(store.isAuthenticated ? "Signed in" : "Guest browsing", systemImage: store.isAuthenticated ? "checkmark.seal" : "person")
                    .font(.sora(12, weight: .medium))
            }
            Text(store.isAuthenticated ? "Notifications are available in Settings." : "Public feeds are available without signing in.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    Image(systemName: symbol)
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

