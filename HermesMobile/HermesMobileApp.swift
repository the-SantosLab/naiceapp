import SwiftUI
import SwiftData

struct HermexSceneActions {
    let canCreateNewChat: Bool
    let createNewChat: () -> Void
    let searchSessions: () -> Void
}

private struct HermexSceneActionsKey: FocusedValueKey {
    typealias Value = HermexSceneActions
}

extension FocusedValues {
    var hermexSceneActions: HermexSceneActions? {
        get { self[HermexSceneActionsKey.self] }
        set { self[HermexSceneActionsKey.self] = newValue }
    }
}

struct HermexCommands: Commands {
    @FocusedValue(\.hermexSceneActions) private var actions
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { actions?.createNewChat() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions?.canCreateNewChat != true)
        }
        CommandGroup(after: .newItem) {
            Button("Search Sessions") { actions?.searchSessions() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}

// MARK: - SwiftData Models

@Model
final class MoodEntry {
    var date: Date
    var mood: String // "good", "neutral", "bad"
    var note: String
    
    init(date: Date, mood: String, note: String) {
        self.date = date; self.mood = mood; self.note = note
    }
}

@Model
final class HabitLog {
    var date: Date
    var habit: String // "walk", "meditation", "reading", "workout", "water"
    var isCompleted: Bool
    var note: String
    
    init(date: Date, habit: String, isCompleted: Bool, note: String) {
        self.date = date; self.habit = habit; self.isCompleted = isCompleted; self.note = note
    }
}

@Model
final class Expense {
    var date: Date
    var amount: Double
    var category: String
    var note: String
    
    init(date: Date, amount: Double, category: String, note: String) {
        self.date = date; self.amount = amount; self.category = category; self.note = note
    }
}

@Model
final class HabitDefinition {
    var name: String
    var icon: String
    var isActive: Bool
    
    init(name: String, icon: String, isActive: Bool = true) {
        self.name = name; self.icon = icon; self.isActive = isActive
    }
}

// MARK: - App

@main
struct HermesMobileApp: App {
    @State private var authManager = AuthManager()
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView(authManager: authManager)
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
        }
        .modelContainer(for: [CachedSession.self, CachedMessage.self, MoodEntry.self, HabitLog.self, Expense.self, HabitDefinition.self])
        .commands { HermexCommands(); SidebarCommands() }
    }
}