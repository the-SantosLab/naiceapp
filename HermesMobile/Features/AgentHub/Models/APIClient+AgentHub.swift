import Foundation

// MARK: - nAIce API Client
@MainActor
class NAiceAPI: ObservableObject {
    static let shared = NAiceAPI()

    @Published var whoop: NAWhoop?
    @Published var ideas: [NAIdea] = []
    @Published var isLoading = false

    func fetchWhoop() async {
        isLoading = true
        let url = URL(string: "https://health.santoslab.de/whoop/summary")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { isLoading = false; return }
        whoop = NAWhoop.from(json)
        isLoading = false
    }

    func fetchIdeas() async {
        guard let url = URL(string: "https://health.santoslab.de/api/naice/ideas") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        ideas = json.compactMap { NAIdea.from($0) }
    }

    func saveIdea(_ text: String) async {
        guard let url = URL(string: "https://health.santoslab.de/api/naice/ideas") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "source": "ios"])
        guard let (data, _) = try? await URLSession.shared.data(for: r),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let is_ = json["ideas"] as? [[String: Any]]
        else { return }
        ideas = is_.compactMap { NAIdea.from($0) }
    }
}