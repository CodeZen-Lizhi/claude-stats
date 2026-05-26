import Foundation
import SwiftUI

struct PricingSettingsView: View {
    @State private var rows: [PricingEditorRow] = PricingEditorRow.rows(from: ModelPricing.loadDefault())
    @State private var statusMessage: String?
    @State private var isUpdating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "Model Pricing",
                caption: "USD per 1M tokens. Saved edits go to ~/.claude-stats/pricing.json."
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Button("Save") { save() }
                            .controlSize(.small)
                        Button {
                            Task { await updateFromOfficialSource() }
                        } label: {
                            if isUpdating {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Update", systemImage: "arrow.clockwise")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isUpdating)
                        Spacer()
                        Text(ModelPricing.userPricingFileURL()?.path ?? "~/.claude-stats/pricing.json")
                            .font(.sora(9))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(12)

                    StxRule()

                    pricingHeader
                    ForEach($rows) { $row in
                        PricingRowEditor(row: $row)
                        if row.id != rows.last?.id { StxRule() }
                    }
                }
                .settingCard()

                if let statusMessage {
                    Text(statusMessage)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pricingHeader: some View {
        HStack(spacing: 8) {
            Text("Model")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Input").frame(width: 62, alignment: .trailing)
            Text("Output").frame(width: 62, alignment: .trailing)
            Text("Cache R").frame(width: 62, alignment: .trailing)
            Text("Cache W").frame(width: 62, alignment: .trailing)
        }
        .font(.sora(9, weight: .semibold))
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func save() {
        do {
            let pricing = PricingEditorRow.pricing(from: rows)
            try ModelPricing.writeUserPricing(pricing)
            statusMessage = L10n.string("pricing.save.success", defaultValue: "Saved pricing. Restart or rescan to apply edited costs to parsed usage.")
        } catch {
            statusMessage = L10n.format("pricing.save.failed", defaultValue: "Save failed: %@", error.localizedDescription)
        }
    }

    @MainActor
    private func updateFromOfficialSource() async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            let result = try await OfficialPricingFetcher().fetch()
            if result.rows.isEmpty {
                statusMessage = L10n.format(
                    "pricing.update.no_machine_readable",
                    defaultValue: "Checked %@, but no machine-readable Codex pricing table was found. Manual editing is still available.",
                    result.source
                )
            } else {
                rows = PricingEditorRow.merge(rows, with: result.rows)
                statusMessage = L10n.format(
                    "pricing.update.success",
                    defaultValue: "Updated %@ model prices from %@.",
                    "\(result.rows.count)",
                    result.source
                )
            }
        } catch {
            statusMessage = L10n.format("pricing.update.failed", defaultValue: "Update failed: %@", error.localizedDescription)
        }
    }
}

private struct PricingEditorRow: Identifiable, Hashable {
    let model: String
    var input: String
    var output: String
    var cacheRead: String
    var cacheWrite: String

    var id: String { model }

    static func rows(from pricing: ModelPricing) -> [PricingEditorRow] {
        pricing.rates
            .map { model, rate in
                PricingEditorRow(
                    model: model,
                    input: decimal(rate.input),
                    output: decimal(rate.output),
                    cacheRead: decimal(rate.cacheRead),
                    cacheWrite: decimal(rate.cacheWrite5m)
                )
            }
            .sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
    }

    static func pricing(from rows: [PricingEditorRow]) -> ModelPricing {
        let rates = Dictionary(uniqueKeysWithValues: rows.map { row in
            let input = Double(row.input) ?? 0
            let output = Double(row.output) ?? 0
            let cacheRead = Double(row.cacheRead) ?? 0
            let cacheWrite = Double(row.cacheWrite) ?? 0
            return (
                row.model,
                ModelPricing.Rates(
                    input: input,
                    output: output,
                    cacheWrite5m: cacheWrite,
                    cacheWrite1h: cacheWrite * 1.6,
                    cacheRead: cacheRead
                )
            )
        })
        return ModelPricing(rates: rates, defaultRate: ModelPricing.loadDefault().defaultRate)
    }

    static func merge(_ existing: [PricingEditorRow], with updates: [PricingEditorRow]) -> [PricingEditorRow] {
        var byModel = Dictionary(uniqueKeysWithValues: existing.map { ($0.model, $0) })
        for update in updates {
            byModel[update.model] = update
        }
        return byModel.values.sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
    }

    fileprivate static func decimal(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}

private struct PricingRowEditor: View {
    @Binding var row: PricingEditorRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.model)
                .font(.sora(11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            pricingField($row.input)
            pricingField($row.output)
            pricingField($row.cacheRead)
            pricingField($row.cacheWrite)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func pricingField(_ value: Binding<String>) -> some View {
        TextField("", text: value)
            .textFieldStyle(.plain)
            .font(.sora(10).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(width: 62)
            .padding(.vertical, 4)
            .padding(.horizontal, 5)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct OfficialPricingFetcher {
    struct Result {
        let source: String
        let rows: [PricingEditorRow]
    }

    private let sourceURL = URL(string: "https://openai.com/api/pricing/")!

    func fetch() async throws -> Result {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 15
        request.setValue("CodexStatistics/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let body = String(decoding: data, as: UTF8.self)
        return Result(source: sourceURL.absoluteString, rows: parseRows(from: body))
    }

    private func parseRows(from body: String) -> [PricingEditorRow] {
        let lines = plainText(from: body)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var rows: [PricingEditorRow] = []

        for index in lines.indices {
            let name = String(lines[index])
            guard name.lowercased().hasPrefix("gpt-") else { continue }
            let window = lines[index..<min(lines.endIndex, index + 16)].joined(separator: "\n")
            guard let input = price(after: "Input:", in: window),
                  let cachedInput = price(after: "Cached input:", in: window),
                  let output = price(after: "Output:", in: window) else { continue }
            rows.append(PricingEditorRow(
                model: canonicalModelName(name),
                input: input,
                output: output,
                cacheRead: cachedInput,
                cacheWrite: PricingEditorRow.decimal((Double(input) ?? 0) * 1.25)
            ))
        }

        return rows
    }

    private func plainText(from html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "\n",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private func price(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker, options: [.caseInsensitive]) else { return nil }
        let rest = text[markerRange.upperBound...]
        guard let dollar = rest.range(of: "$") else { return nil }
        let number = rest[dollar.upperBound...]
            .prefix { $0.isNumber || $0 == "." }
        return number.isEmpty ? nil : String(number)
    }

    private func canonicalModelName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
    }
}

#if DEBUG
#Preview {
    PricingSettingsView()
        .padding()
        .frame(width: 820)
        .background(Color.stxBackground)
}
#endif
