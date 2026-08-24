import Foundation

// MARK: - Rollup Service (console.naice.app/api/v2/rollup)
@MainActor
class NARollupService: ObservableObject {
    static let shared = NARollupService()

    private let baseURL = URL(string: "https://health.santoslab.de/api/naice/rollup")!
    private let authToken = "08732b...1bf2" // LOVABLE_API_KEY from naice-console

    @Published var rollup: NARollup? = nil
    @Published var isLoading = false
    @Published var lastError: String? = nil

    func fetch() async {
        isLoading = true
        lastError = nil

        var req = URLRequest(url: baseURL)
        req.setValue(authToken, forHTTPHeaderField: "x-auth-token")
        req.timeoutInterval = 15

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200
        else {
            lastError = "Verbindung fehlgeschlagen"
            isLoading = false
            return
        }

        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(NARollup.self, from: data)
            self.rollup = decoded
            self.isLoading = false
            print("[Rollup]✅ Erfolg: \(decoded.business?.foodloop?.total ?? 0) foodloop, \(decoded.deals?.active_deals ?? 0) deals")
        } catch {
            self.lastError = "Dekodierung: \(error.localizedDescription)"
            self.isLoading = false
            print("[Rollup]❌ Decode Error: \(error)")
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