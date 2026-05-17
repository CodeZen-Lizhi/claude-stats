import Foundation

enum CostEstimationMode: String, CaseIterable, Sendable, Identifiable {
    case standardAPI
    case detailedBilling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standardAPI: "API estimate"
        case .detailedBilling: "Detailed billing"
        }
    }
}

struct CostEstimate: Sendable, Hashable {
    var standardAPI: Double
    var detailedBilling: Double

    static let zero = CostEstimate(standardAPI: 0, detailedBilling: 0)

    init(standardAPI: Double, detailedBilling: Double? = nil) {
        self.standardAPI = standardAPI
        self.detailedBilling = detailedBilling ?? standardAPI
    }

    func value(for mode: CostEstimationMode) -> Double {
        switch mode {
        case .standardAPI: standardAPI
        case .detailedBilling: detailedBilling
        }
    }

    static func + (lhs: CostEstimate, rhs: CostEstimate) -> CostEstimate {
        CostEstimate(
            standardAPI: lhs.standardAPI + rhs.standardAPI,
            detailedBilling: lhs.detailedBilling + rhs.detailedBilling
        )
    }

    static func += (lhs: inout CostEstimate, rhs: CostEstimate) { lhs = lhs + rhs }
}
