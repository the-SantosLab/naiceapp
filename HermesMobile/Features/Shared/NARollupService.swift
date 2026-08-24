import Foundation

// MARK: - Rollup Service (console.naice.app/api/v2/rollup)
@MainActor
class NARollupService: ObservableObject {
    static let shared = NARollupService()

    private let baseURL = URL(string: "https://health.santoslab.de/api/naice/rollup")!

    @Published var rollup: NARollup? = nil
    @Published var isLoading = false
    @Published var lastError: String? = nil

    func fetch() async {
        guard !Task.isCancelled else { return }
        isLoading = true
        lastError = nil

        var req = URLRequest(url: baseURL)
        req.timeoutInterval = 30

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard !Task.isCancelled else { return }
            guard let http = resp as? HTTPURLResponse else {
                lastError = "Keine HTTP-Response"
                isLoading = false
                return
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                lastError = "HTTP \(http.statusCode): \(body)"
                isLoading = false
                return
            }

            let decoded = try JSONDecoder().decode(NARollup.self, from: data)
            self.rollup = decoded
            self.isLoading = false
            print("[Rollup]✅ Erfolg: \(decoded.business?.foodloop?.total ?? 0) foodloop, \(decoded.deals?.active_deals ?? 0) deals")
        } catch {
            lastError = "\(error.localizedDescription)"
            isLoading = false
            print("[Rollup]❌ Error: \(error)")
        }
    }

    var whoop: NAWhoopRollup? { rollup?.whoop }
    var business: NABusinessRollup? { rollup?.business }
    var tasks: NATasksRollup? { rollup?.tasks }
    var deals: NADealsRollup? { rollup?.deals }
    var summary: NASummary? { rollup?.summary }
    var journal: NAJournalRollup? { rollup?.journal }
    var calendar: NACalendarRollup? { rollup?.calendar }
    var flags: [NASummaryFlag] { summary?.flags ?? [] }
}