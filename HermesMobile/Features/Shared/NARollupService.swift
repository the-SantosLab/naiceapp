import Foundation

// MARK: - Rollup Service (console.naice.app/api/v2/rollup)
@MainActor
@Observable
class NARollupService {
    static let shared = NARollupService()

    private let baseURL = URL(string: "https://console.naice.app/api/v2/rollup")!
    private let authToken = "08732b...1bf2" // LOVABLE_API_KEY from naice-console

    var rollup: NARollup?
    var isLoading = false
    var lastError: String?

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
            rollup = try decoder.decode(NARollup.self, from: data)
            isLoading = false
        } catch {
            lastError = "Dekodierung fehlgeschlagen: \(error.localizedDescription)"
            isLoading = false
            print("[Rollup] Decode error: \(error)")
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