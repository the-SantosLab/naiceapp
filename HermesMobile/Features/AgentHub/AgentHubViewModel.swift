import SwiftUI
import SwiftData

// MARK: - AgentHub ViewModel
@MainActor
@Observable
class AgentHubViewModel {
    var whoop: NAWhoop?
    var ideas: [NAIdea] = []
    var isLoading = false
    var showIdea = false
    var newIdea = ""

    private let api = NAiceAPI.shared

    func refresh() async {
        await api.fetchWhoop()
        whoop = api.whoop
        await api.fetchIdeas()
        ideas = api.ideas
    }

    func saveIdea() async {
        guard !newIdea.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = newIdea
        newIdea = ""
        showIdea = false
        await api.saveIdea(text)
        ideas = api.ideas
    }
}