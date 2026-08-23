import SwiftUI
import SwiftData
import HealthKit
import EventKit

// MARK: - ContentView

struct ContentView: View {
    @Bindable var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ResponseCompletionNotifications.isEnabledKey) private var isResponseCompletionNotificationsEnabled = false
    @State private var pendingSharedImport: SharedImport?
    @State private var pendingDeepLinkedSessionID: String?
    @State private var pendingNewChatRequest: NewChatRequest?
    @State private var didCheckInitialPendingShare = false
    @State private var intentRouter = AppIntentRouter.shared

    var body: some View {
        content.onOpenURL(perform: handleOpenURL)
            .task { guard !didCheckInitialPendingShare else { return }; didCheckInitialPendingShare = true; importPendingSharedDraftIfAvailable(); drainPendingIntentDeepLink() }
            .onChange(of: intentRouter.pendingDeepLink) { drainPendingIntentDeepLink() }
            .task { await reconcileOrphanedLiveActivities(notifiesOnCompletion: true) }
            .onChange(of: scenePhase) { guard scenePhase == .active else { return }; importPendingSharedDraftIfAvailable(); Task { await reconcileOrphanedLiveActivities(notifiesOnCompletion: false) } }
    }
    private func reconcileOrphanedLiveActivities(notifiesOnCompletion: Bool) async {
        guard case let .loggedIn(server) = authManager.state else { return }
        await LiveActivityReconciler.reconcileOrphanedActivities(server: server, notifiesOnCompletion: notifiesOnCompletion, preferenceEnabled: isResponseCompletionNotificationsEnabled)
    }
    @ViewBuilder private var content: some View {
        switch authManager.state {
        case .unconfigured: OnboardingView(authManager: authManager)
        case .loggedOut(let server): OnboardingView(authManager: authManager, savedServer: server)
        case .loggedIn(let server): NAIceTabView(authManager: authManager, server: server).id(server)
        }
    }
    private func handleOpenURL(_ url: URL) {
        if HermesDeepLink.isNewChatVoiceURL(url) { pendingNewChatRequest = NewChatRequest(autoStartsVoiceInput: true); return }
        if HermesDeepLink.isNewChatInProfileURL(url) { pendingNewChatRequest = NewChatRequest(profileName: HermesDeepLink.profileName(fromNewChatInProfile: url)); return }
        if HermesDeepLink.isNewChatURL(url) { pendingNewChatRequest = NewChatRequest(autoStartsVoiceInput: false); return }
        if let sessionID = HermesDeepLink.sessionID(from: url) { pendingDeepLinkedSessionID = sessionID; return }
        guard HermesShareDraft.isShareOpenURL(url) else { return }; importPendingSharedDraftIfAvailable()
    }
    private func drainPendingIntentDeepLink() { guard let url = intentRouter.pendingDeepLink else { return }; intentRouter.pendingDeepLink = nil; handleOpenURL(url) }
    private func importPendingSharedDraftIfAvailable() {
        guard let directory = HermesShareDraft.containerURL() else { return }
        do { if let si = try HermesShareDraft.loadPendingImport(from: directory) { pendingSharedImport = si } } catch { pendingSharedImport = nil }
    }
}

// MARK: - nAIce Warm Design System

extension Color {
    static let ncCream = Color(red: 0.984, green: 0.957, blue: 0.886)
    static let ncPaper = Color(red: 1.0, green: 0.973, blue: 0.906)
    static let ncSand = Color(red: 0.910, green: 0.863, blue: 0.769)
    static let ncSage = Color(red: 0.541, green: 0.608, blue: 0.478)
    static let ncGreen = Color(red: 0.239, green: 0.353, blue: 0.278)
    static let ncDark = Color(red: 0.102, green: 0.078, blue: 0.051)
    static let ncMuted = Color(red: 0.541, green: 0.510, blue: 0.439)
    static let ncRed = Color(red: 0.761, green: 0.231, blue: 0.231)
    static let ncGold = Color(red: 0.769, green: 0.635, blue: 0.396)
}

struct NAIceCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ncSand.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }
}

struct NAIceSectionLabel: View {
    let icon: String; let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundColor(.ncSage)
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.ncSage).textCase(.uppercase)
        }.padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 6)
    }
}

struct NAiceSmallButton: View {
    let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.semibold)).foregroundColor(.ncGreen)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.ncGreen.opacity(0.15), lineWidth: 0.5))
        }
    }
}

// MARK: - HealthKit Manager

@MainActor
class HealthManager: ObservableObject {
    static let shared = HealthManager()
    let store = HKHealthStore()
    @Published var steps: Int = 0
    @Published var heartRate: Double = 0
    @Published var hrv: Double = 0
    @Published var sleepHours: Double = 0
    @Published var isAuthorized = false

    func requestAuth() async {
        let types: Set = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do { try await store.requestAuthorization(toShare: [], read: types); isAuthorized = true; await loadAll() }
        catch { print("HK skipped: \(error.localizedDescription)"); isAuthorized = false }
    }
    func loadAll() async {
        let cal = Calendar.current; let today = cal.startOfDay(for: Date()); let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let predicate = HKQuery.predicateForSamples(withStart: today, end: tomorrow, options: .strictStartDate)
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) {
            let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in
                let q = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, s, _ in c.resume(returning: s?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0) }
                store.execute(q)
            }
            steps = Int(r ?? 0)
        }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in
                let q = HKSampleQuery(sampleType: t, predicate: predicate, limit: 1, sortDescriptors: [.init(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, s, _ in c.resume(returning: (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit(from: "count/min")) ?? 0) }
                store.execute(q)
            }
            heartRate = r ?? 0
        }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in
                let q = HKSampleQuery(sampleType: t, predicate: predicate, limit: 1, sortDescriptors: [.init(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, s, _ in c.resume(returning: (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) ?? 0) }
                store.execute(q)
            }
            hrv = r ?? 0
        }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in
                let q = HKSampleQuery(sampleType: t, predicate: predicate, limit: 1, sortDescriptors: [.init(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, s, _ in
                    let sec = (s?.first as? HKCategorySample).map { $0.endDate.timeIntervalSince($0.startDate) } ?? 0
                    c.resume(returning: sec / 3600)
                }
                store.execute(q)
            }
            sleepHours = r ?? 0
        }
    }
}

// MARK: - Calendar Manager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    let store = EKEventStore()
    @Published var todayEvents: [EKEvent] = []
    @Published var isAuthorized = false
    func requestAuth() async {
        guard EKEventStore.authorizationStatus(for: .event) != .denied else { return }
        do { if #available(iOS 17, *) { isAuthorized = try await store.requestFullAccessToEvents() } else { isAuthorized = try await store.requestAccess(to: .event) }; if isAuthorized { await loadToday() } }
        catch { print("Cal skipped: \(error.localizedDescription)"); isAuthorized = false }
    }
    func loadToday() async {
        let cal = Calendar.current; let today = cal.startOfDay(for: Date()); let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        todayEvents = store.events(matching: store.predicateForEvents(withStart: today, end: tomorrow, calendars: nil))
    }
}

// MARK: - Tab View

@MainActor
struct NAIceTabView: View {
    @Bindable var authManager: AuthManager
    let server: URL
    @State private var selectedTab: Tab = .home
    @State private var pendingSharedImport: SharedImport?
    @State private var pendingDeepLinkedSessionID: String?
    @State private var pendingNewChat: NewChatRequest?
    @StateObject private var health = HealthManager.shared
    @StateObject private var calendar = CalendarManager.shared

    enum Tab: String, CaseIterable {
        case home; case life; case agent; case more
        var title: String { switch self {
        case .home: return "Home"; case .life: return "Leben"
        case .agent: return "Agent"; case .more: return "Mehr" }
        }
        var icon: String { switch self {
        case .home: return "house"; case .life: return "leaf"
        case .agent: return "bubble.left.and.bubble.right"; case .more: return "square.grid.2x2" }
        }
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { NAIceHomeView(health: health, calendar: calendar) }
                .tabItem { Label(Tab.home.title, systemImage: Tab.home.icon) }.tag(Tab.home)
            NavigationStack { NAIceLifeView() }
                .tabItem { Label(Tab.life.title, systemImage: Tab.life.icon) }.tag(Tab.life)
            SessionListView(authManager: authManager, server: server,
                pendingSharedImport: $pendingSharedImport, pendingDeepLinkedSessionID: $pendingDeepLinkedSessionID, requestedNewChat: $pendingNewChat)
                .tabItem { Label(Tab.agent.title, systemImage: Tab.agent.icon) }.tag(Tab.agent)
            NavigationStack { NAIceMoreView() }
                .tabItem { Label(Tab.more.title, systemImage: Tab.more.icon) }.tag(Tab.more)
        }
        .tint(Color.ncGreen)
        .task { await health.requestAuth(); await calendar.requestAuth() }
    }
}

// MARK: - Home View

struct NAIceHomeView: View {
    @ObservedObject var health: HealthManager
    @ObservedObject var calendar: CalendarManager
    @Query(sort: \MoodEntry.date, order: .reverse) var moods: [MoodEntry]
    @Query(sort: \HabitLog.date, order: .reverse) var habits: [HabitLog]
    @Environment(\.modelContext) var mc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Greeting
                NAIceCard {
                    HStack(spacing: 14) {
                        Circle().fill(Color.ncGreen).frame(width: 48, height: 48)
                            .overlay(Image(systemName: "person.fill").font(.title3).foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hallo Johannes").font(.headline.weight(.bold)).foregroundColor(.ncDark)
                            Text(moodSuggestion()).font(.subheadline).foregroundColor(.ncMuted)
                        }
                    }
                    if let last = moods.first {
                        HStack { Image(systemName: moodIcon(last.mood)).foregroundColor(moodColor(last.mood)); Text(moodText(last.mood)).font(.caption).foregroundColor(.ncMuted) }.padding(.top, 4)
                    }
                }
                // QuickLog - direkt auf Home
                QuickLogCard(mc: mc)
                // Kalender
                if !calendar.todayEvents.isEmpty {
                    NAIceCard {
                        HStack { Text("Heute").font(.subheadline.weight(.semibold)).foregroundColor(.ncSage).textCase(.uppercase); Spacer(); Text("\(calendar.todayEvents.count) Termine").font(.caption).foregroundColor(.ncMuted) }
                        ForEach(calendar.todayEvents, id: \.eventIdentifier) { ev in
                            HStack(spacing: 8) { Circle().fill(Color.ncSage).frame(width: 6, height: 6); Text(ev.title ?? "").font(.subheadline).foregroundColor(.ncDark); Spacer(); Text(ev.startDate, style: .time).font(.caption).foregroundColor(.ncMuted) }
                        }
                    }
                }
                // Health
                if health.isAuthorized {
                    NAIceCard {
                        Text("Gesundheit heute").font(.subheadline.weight(.semibold)).foregroundColor(.ncSage).textCase(.uppercase)
                        HStack(spacing: 16) {
                            healthMini(title: "Schritte", value: "\(health.steps)", icon: "figure.walk")
                            healthMini(title: "Puls", value: "\(Int(health.heartRate))", icon: "heart.fill")
                            healthMini(title: "HRV", value: "\(Int(health.hrv))ms", icon: "waveform.path.ecg")
                            healthMini(title: "Schlaf", value: String(format: "%.1fh", health.sleepHours), icon: "moon.fill")
                        }
                    }
                }
                // Mood
                NAIceCard {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text("Wie geht es dir...").font(.headline.weight(.semibold)).foregroundColor(.ncDark); if moods.isEmpty { Text("Ein Tipp – und der Agent lernt dich besser kennen.").font(.subheadline).foregroundColor(.ncMuted) } }; Spacer(); Text("\u{1F60A}").font(.title2) }
                    NavigationLink(destination: NAIceMoodView()) { Text("Jetzt eintragen").font(.subheadline.weight(.semibold)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 10)) }.padding(.top, 4)
                }
                // Dein Tag
                NAIceCard {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text("Dein Tag").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text(calendar.todayEvents.isEmpty ? "Keine Termine – Zeit fur deine Projekte" : "\(calendar.todayEvents.count) Termine heute").font(.subheadline).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: calendar.todayEvents.isEmpty ? "sun.max.fill" : "calendar.badge.checkmark").foregroundColor(calendar.todayEvents.isEmpty ? .ncGold : .ncGreen) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Color.ncCream.ignoresSafeArea())
        .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
    }
    func healthMini(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) { Image(systemName: icon).font(.caption).foregroundColor(.ncSage); Text(value).font(.callout.weight(.bold)).foregroundColor(.ncDark); Text(title).font(.caption2).foregroundColor(.ncMuted) }.frame(maxWidth: .infinity)
    }
    func moodSuggestion() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 6 { return "Nachtruhe? Ich bin trotzdem fur dich da." }; if h < 9 { return "Guten Morgen! Bereit fur den Tag?" }; if h < 12 { return "Vormittag – Zeit fur wichtige Dinge." }; if h < 14 { return "Mittagspause? Ich halte dir den Rucken frei." }; if h < 17 { return "Nachmittag – wie lauft es?" }; if h < 21 { return "Feierabend – alles gut?" }
        return "Gute Nacht. Ich bin morgen wieder da."
    }
    func moodIcon(_ m: String) -> String { m == "good" ? "hand.thumbsup.fill" : m == "neutral" ? "hand.thumbsup" : "hand.thumbsdown" }
    func moodColor(_ m: String) -> Color { m == "good" ? .ncGreen : m == "neutral" ? .ncGold : .ncRed }
    func moodText(_ m: String) -> String { m == "good" ? "Gut gelaunt heute" : m == "neutral" ? "Neutral" : "Nicht so gut" }
}

// MARK: - QuickLog (Inline Mood & Habit)

struct QuickLogCard: View {
    let mc: ModelContext
    @State private var mood: String? = nil
    @State private var showMood = false
    @State private var showHabit = false

    var body: some View {
        NAIceCard {
            HStack { Text("QuickLog").font(.subheadline.weight(.semibold)).foregroundColor(.ncSage).textCase(.uppercase); Spacer()
                Button { showMood = true } label: { Image(systemName: "face.smiling").font(.body).foregroundColor(.ncSage) }
                Button { showHabit = true } label: { Image(systemName: "plus.circle").font(.body).foregroundColor(.ncSage) }
            }
            if !showMood && !showHabit {
                Text("Schnell erfassen: Wie fuhlst du dich oder was hast du gemacht?").font(.subheadline).foregroundColor(.ncMuted)
            }
            if showMood {
                HStack(spacing: 20) {
                    Button { mc.insert(MoodEntry(date: Date(), mood: "good", note: "")); try? mc.save(); showMood = false } label: { VStack { Text("\u{1F60A}").font(.title2); Text("Gut").font(.caption2).foregroundColor(.ncMuted) } }
                    Button { mc.insert(MoodEntry(date: Date(), mood: "neutral", note: "")); try? mc.save(); showMood = false } label: { VStack { Text("\u{1F610}").font(.title2); Text("Neutral").font(.caption2).foregroundColor(.ncMuted) } }
                    Button { mc.insert(MoodEntry(date: Date(), mood: "bad", note: "")); try? mc.save(); showMood = false } label: { VStack { Text("\u{1F614}").font(.title2); Text("Nicht gut").font(.caption2).foregroundColor(.ncMuted) } }
                    Button { showMood = false } label: { Text("X").font(.caption).foregroundColor(.ncSand) }
                }
            }
            if showHabit {
                HStack(spacing: 12) {
                    ForEach([("walk","figure.walk"), ("water","drop.fill"), ("reading","book.fill"), ("workout","dumbbell.fill"), ("meditation","brain.head.profile")], id: \.0) { h, icon in
                        Button { mc.insert(HabitLog(date: Date(), habit: h, isCompleted: true, note: "")); try? mc.save(); showHabit = false } label: { Image(systemName: icon).font(.title3).foregroundColor(.ncSage).frame(width: 36, height: 36).background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }
                    }
                    Button { showHabit = false } label: { Text("X").font(.caption).foregroundColor(.ncSand) }
                }
            }
        }
    }
}

// MARK: - Mood View

struct NAIceMoodView: View {
    @Environment(\.modelContext) var mc
    @Environment(\.dismiss) var dismiss
    @Query(sort: \MoodEntry.date, order: .reverse) var moods: [MoodEntry]
    @State private var selectedMood: String = "good"
    @State private var note: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Wie fuhlst du dich?").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                HStack(spacing: 20) {
                    moodButton("good", "\u{1F60A}", "Gut"); moodButton("neutral", "\u{1F610}", "Neutral"); moodButton("bad", "\u{1F614}", "Nicht gut")
                }
                TextField("Notiz (optional)", text: $note).padding(12).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                Button("Eintragen") { mc.insert(MoodEntry(date: Date(), mood: selectedMood, note: note)); try? mc.save(); dismiss() }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14))
                if !moods.isEmpty {
                    NAIceSectionLabel(icon: "clock", title: "Verlauf")
                    ForEach(Array(moods.prefix(14))) { entry in
                        NAIceCard {
                            HStack { Text(moodEmoji(entry.mood)).font(.title3); VStack(alignment: .leading, spacing: 2) { Text(moodText(entry.mood)).font(.subheadline.weight(.medium)).foregroundColor(.ncDark); Text(entry.date, style: .date).font(.caption).foregroundColor(.ncMuted) }; Spacer(); if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundColor(.ncMuted).lineLimit(1) } }
                        }
                    }
                }
            }.padding(20)
        }.background(Color.ncCream.ignoresSafeArea()).navigationTitle("Mood").navigationBarTitleDisplayMode(.inline)
    }
    func moodButton(_ m: String, _ emoji: String, _ label: String) -> some View {
        Button { selectedMood = m } label: { VStack(spacing: 8) { Text(emoji).font(.system(size: 40)); Text(label).font(.caption).foregroundColor(.ncMuted) }.padding(16).background(RoundedRectangle(cornerRadius: 14).fill(selectedMood == m ? Color.ncGreen.opacity(0.08) : Color.ncPaper)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedMood == m ? Color.ncGreen : Color.ncSand, lineWidth: selectedMood == m ? 1.5 : 0.5)) }
    }
    func moodEmoji(_ m: String) -> String { m == "good" ? "\u{1F60A}" : m == "neutral" ? "\u{1F610}" : "\u{1F614}" }
    func moodText(_ m: String) -> String { m == "good" ? "Gut" : m == "neutral" ? "Neutral" : "Nicht gut" }
}

// MARK: - Life View

struct NAIceLifeView: View {
    @Query(sort: \HabitLog.date, order: .reverse) var habits: [HabitLog]
    @Query(sort: \Expense.date, order: .reverse) var expenses: [Expense]
    @State private var showExpense = false
    @State private var showHabitLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dein Leben").font(.title2.weight(.bold)).foregroundColor(.ncDark).padding(.horizontal, 4).padding(.top, 4)

                // Mein Leben → Detail mit Tipps
                NavigationLink(destination: NAiceDetailPage(title: "Mein Leben", icon: "heart.fill", tips: ["Deine Gesundheitsdaten werden mit HealthKit synchronisiert.", "Tippe auf Gewohnheiten, um deine tägliche Challenge zu sehen.", "Verbinde Whoop fur erweiterte Schlaf- und Erholungsdaten."])) {
                    NAIceCard { HStack(spacing: 12) { Image(systemName: "heart.fill").font(.title2).foregroundColor(.ncGreen); Text("Mein Leben").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }; Text("Tippen fur Details").font(.subheadline).foregroundColor(.ncMuted).padding(.top, 2) }
                }.buttonStyle(PlainButtonStyle())

                // nAIce Insights
                NAIceCard {
                    HStack { Image(systemName: "lightbulb.fill").font(.title2).foregroundColor(.ncGold); Text("nAIce Insights").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }
                    Text("Verbinde Dienste (Health, Kalender, Reminders) fur personalisierte Insights.").font(.subheadline).foregroundColor(.ncMuted).padding(.top, 2)
                    HStack(spacing: 6) {
                        Text(healthConnected() ? "HealthKit verbunden" : "HealthKit").font(.caption).foregroundColor(healthConnected() ? .ncGreen : .ncSage).padding(.horizontal, 8).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 6).fill(healthConnected() ? Color.ncGreen.opacity(0.08) : Color.ncSand.opacity(0.2)))
                        Text(calConnected() ? "Kalender verbunden" : "Kalender").font(.caption).foregroundColor(calConnected() ? .ncGreen : .ncSage).padding(.horizontal, 8).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 6).fill(calConnected() ? Color.ncGreen.opacity(0.08) : Color.ncSand.opacity(0.2)))
                    }.padding(.top, 4)
                }

                // Whoop → Detail mit Tipps
                NavigationLink(destination: NAiceDetailPage(title: "Whoop", icon: "heart.circle", tips: ["Whoop misst deine Erholung, Belastung und Schlafqualitat.", "Der Recovery Score zeigt, ob dein Korper bereit fur Training ist.", "HRV (Herzfrequenzvariabilitat) ist ein Indikator fur dein autonomes Nervensystem.", "Daten werden automatisch vom Whoop-Server geladen."])) {
                    NAIceCard {
                        Text("Whoop").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Text("Zeigt Recovery Score, HRV, Ruhepuls und Strain im Dashboard.").font(.subheadline).foregroundColor(.ncMuted)
                        Text("Whoop ist auf dem Server eingerichtet.").font(.caption).foregroundColor(.ncSage).padding(.top, 2)
                        HStack { Image(systemName: "heart.circle").font(.title3).foregroundColor(.ncGreen); Text("Whoop verbinden").font(.subheadline.weight(.medium)).foregroundColor(.ncGreen) }
                            .padding(.horizontal, 16).padding(.vertical, 10).background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncGreen.opacity(0.15), lineWidth: 0.5))
                    }
                }.buttonStyle(PlainButtonStyle())

                // Gewohnheiten → Detail
                NavigationLink(destination: NAIceHabitsView()) {
                    NAIceCard {
                        HStack { Text("Gewohnheiten").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }
                        Text(habits.isEmpty ? "Heute noch nichts geloggt" : "\(habits.filter { Calendar.current.isDateInToday($0.date) }.count) heute geloggt").font(.subheadline).foregroundColor(.ncMuted)
                        HStack(spacing: 10) {
                            Image(systemName: "figure.walk").font(.title3).foregroundColor(.ncSage)
                            VStack(alignment: .leading, spacing: 1) { Text("Heutige Challenge:").font(.caption).foregroundColor(.ncMuted); Text("Gehe 15 Min Spazieren").font(.subheadline.weight(.medium)).foregroundColor(.ncDark) }
                            Spacer(); NAiceSmallButton(label: "Loggen") { showHabitLog = true }
                        }
                    }
                }.buttonStyle(PlainButtonStyle())

                // Finanzen → Detail
                NavigationLink(destination: NAIceFinanceView()) {
                    NAIceCard {
                        HStack { VStack(alignment: .leading, spacing: 2) { Text("Finanzen").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Tippen fur Budget & Analyse").font(.caption).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }
                        let monthly = expenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) { Text("Ausgaben").font(.caption).foregroundColor(.ncMuted); Text("\(Int(monthly.reduce(0) { $0 + $1.amount })) Euro").font(.title3.weight(.bold)).foregroundColor(.ncGreen) }
                            Divider().frame(height: 30)
                            VStack(alignment: .leading, spacing: 2) { Text("Kategorien").font(.caption).foregroundColor(.ncMuted); Text("\(Set(monthly.map { $0.category }).count)").font(.title3.weight(.bold)).foregroundColor(.ncDark) }
                        }.padding(.top, 6)
                    }
                }.buttonStyle(PlainButtonStyle())

                // Menschen mit Kontakt auffrischen
                NavigationLink(destination: NAiceDetailPage(title: "Menschen", icon: "person.2.fill", tips: ["Jochen Rupp – Kontakt zuletzt aktualisiert vor 3 Monaten.", "Martin Grassl – Kontakt zuletzt aktualisiert vor 2 Monaten.", "nAIce schlagt vor, Kontakte aufzufrischen, wenn sie alter als 30 Tage sind.", "Nach 14 Tagen ohne Geburtstag: ruhige Phase – keine Aktion notig."])) {
                    NAIceCard {
                        HStack { Text("Menschen").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }
                        Text("Keine Geburtstage in den nachsten 14 Tagen – ruhige Phase.").font(.subheadline).foregroundColor(.ncMuted).padding(.top, 2)
                        VStack(spacing: 8) {
                            contactRow(name: "Jochen Rupp", showRefresh: true)
                            Divider().foregroundColor(.ncSand.opacity(0.3))
                            contactRow(name: "Martin Grassl", showRefresh: true)
                        }.padding(.top, 4)
                    }
                }.buttonStyle(PlainButtonStyle())

                // Apple Daten
                NAIceCard {
                    HStack { Image(systemName: "apple.logo").font(.title2).foregroundColor(.ncDark); Text("Apple Daten").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "checkmark.circle.fill").foregroundColor(.ncGreen).font(.title3) }
                    Text("Alles aktuell – keine anstehenden Termine oder Aufgaben.").font(.subheadline).foregroundColor(.ncMuted).padding(.top, 2)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Color.ncCream.ignoresSafeArea())
        .navigationTitle("Leben").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHabitLog) { HabitLogSheet() }
    }

    func contactRow(name: String, showRefresh: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.ncSage.opacity(0.3)).frame(width: 32, height: 32).overlay(Text(String(name.prefix(1))).font(.caption.weight(.bold)).foregroundColor(.ncDark))
            Text(name).font(.subheadline).foregroundColor(.ncDark)
            Spacer()
            if showRefresh { Button("Kontakt auffrischen?") {}.font(.caption).foregroundColor(.ncGreen) }
        }
    }
    func healthConnected() -> Bool { HealthManager.shared.isAuthorized }
    func calConnected() -> Bool { CalendarManager.shared.isAuthorized }
}

// MARK: - Detail Page mit AI-Tipps

struct NAiceDetailPage: View {
    let title: String
    let icon: String
    let tips: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NAIceCard {
                    HStack(spacing: 14) {
                        Image(systemName: icon).font(.title).foregroundColor(.ncGreen).frame(width: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.title2.weight(.bold)).foregroundColor(.ncDark)
                            Text("Erkunde Details und erhalte personalisierte Tipps.").font(.subheadline).foregroundColor(.ncMuted)
                        }
                    }
                }

                NAIceCard {
                    Text("AI-Tipps fur dich").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    ForEach(Array(tips.enumerated()), id: \.offset) { idx, tip in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(idx + 1)").font(.caption.weight(.bold)).foregroundColor(.ncSage).frame(width: 20)
                            Text(tip).font(.subheadline).foregroundColor(.ncMuted).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    }
                }

                NAIceCard {
                    HStack { Image(systemName: "sparkles").font(.title3).foregroundColor(.ncGold); Text("nAIce Agent").font(.headline.weight(.semibold)).foregroundColor(.ncDark) }
                    Text("Frage deinen Agenten fur weitere Informationen zu diesem Thema im Chat.").font(.subheadline).foregroundColor(.ncMuted)
                    NavigationLink(destination: Text("Agent Chat")) { Text("Zum Agent").font(.subheadline.weight(.semibold)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 10)) }.padding(.top, 4)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Color.ncCream.ignoresSafeArea())
        .navigationTitle(title).navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Habit Log Sheet

struct HabitLogSheet: View {
    @Environment(\.modelContext) var mc; @Environment(\.dismiss) var dismiss
    @State private var selected: String = "walk"; @State private var note = ""
    let options = [("walk","figure.walk","Spazieren"),("water","drop.fill","Wasser"),("reading","book.fill","Lesen"),("workout","dumbbell.fill","Training"),("meditation","brain.head.profile","Meditation")]
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Gewohnheit loggen").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())], spacing: 12) {
                    ForEach(options, id: \.0) { opt in
                        Button { selected = opt.0 } label: { VStack(spacing: 6) { Image(systemName: opt.1).font(.title2).foregroundColor(selected == opt.0 ? .white : .ncSage).frame(width: 36,height: 36).background(selected == opt.0 ? Color.ncGreen : Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)); Text(opt.2).font(.caption).foregroundColor(.ncDark) }.padding(10).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(Color.ncPaper)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == opt.0 ? Color.ncGreen : Color.ncSand, lineWidth: selected == opt.0 ? 1.5 : 0.5)) }
                    }
                }
                TextField("Notiz (optional)", text: $note).padding(12).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                Button("Loggen") { mc.insert(HabitLog(date: Date(), habit: selected, isCompleted: true, note: note)); try? mc.save(); dismiss() }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14))
            }.padding(20).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundColor(.ncMuted) } }
        }
    }
}

// MARK: - Habits Detail

struct NAIceHabitsView: View {
    @Query(sort: \HabitLog.date, order: .reverse) var allLogs: [HabitLog]
    private var thisWeek: [HabitLog] { let cal = Calendar.current; let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!; return allLogs.filter { $0.date >= start } }
    private let challenges = ["Gehe 15 Min Spazieren","Trinke 2L Wasser","10 Min Meditieren","20 Min Lesen","5 Min Tagebuch","Dehnubungen 10 Min"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NAIceCard { HStack { Image(systemName: "star.fill").font(.title2).foregroundColor(.ncGold); Text("Heutige Challenge").font(.headline.weight(.semibold)).foregroundColor(.ncDark) }; Text(challenges[Calendar.current.component(.day, from: Date()) % challenges.count]).font(.body.weight(.medium)).foregroundColor(.ncDark).padding(.top, 2); Text("Diese Challenge wurde fur dich ausgewahlt.").font(.caption).foregroundColor(.ncMuted) }
                NAIceCard { Text("Wochen-Ruckblick").font(.headline.weight(.semibold)).foregroundColor(.ncDark); if thisWeek.isEmpty { Text("Diese Woche noch keine Gewohnheiten geloggt. Starte heute! \u{1F4AA}").font(.subheadline).foregroundColor(.ncMuted).padding(.top, 4) }; let days = ["Mo","Di","Mi","Do","Fr","Sa","So"]; VStack(spacing: 0) { ForEach(Array(days.enumerated()), id: \.offset) { idx, day in let dayDate = Calendar.current.date(byAdding: .day, value: idx - Calendar.current.component(.weekday, from: Date()) + 1, to: Date()) ?? Date(); let count = thisWeek.filter { Calendar.current.isDate($0.date, inSameDayAs: dayDate) }.count; HStack(spacing: 12) { Text(day).font(.subheadline.weight(.medium)).foregroundColor(.ncMuted).frame(width: 28, alignment: .leading); RoundedRectangle(cornerRadius: 4).fill(count > 0 ? Color.ncGreen : Color.ncSand.opacity(0.3)).frame(height: 18); Text("\(count)").font(.caption).foregroundColor(.ncMuted).frame(width: 20) }.padding(.vertical, 6); if idx < 6 { Divider().foregroundColor(.ncSand.opacity(0.3)) } } }; let pct = days.isEmpty ? 0 : Double(thisWeek.count) / Double(days.count * 3) * 100; ProgressView(value: min(pct / 100, 1)).tint(.ncGreen).padding(.top, 6); Text("\(Int(min(pct, 100))) % abgeschlossen").font(.caption).foregroundColor(.ncMuted) }
                if !allLogs.isEmpty { NAIceCard { Text("Letzte Eintrage").font(.headline.weight(.semibold)).foregroundColor(.ncDark); ForEach(Array(allLogs.prefix(5))) { log in HStack { Circle().fill(Color.ncGreen).frame(width: 8,height: 8); Text(log.habit).font(.subheadline).foregroundColor(.ncDark); Spacer(); Text(log.date, style: .relative).font(.caption).foregroundColor(.ncMuted) }.padding(.vertical, 2) } } }
                let streak = calculateStreak()
                NAIceCard { HStack { Image(systemName: "flame.fill").font(.title2).foregroundColor(.ncGold); Text("Serie").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Text("\(streak) Tage").font(.title2.weight(.bold)).foregroundColor(.ncGreen) }; Text(streak > 0 ? "Weiter so! \u{1F44F}" : "Starte heute deine Serie!").font(.subheadline).foregroundColor(.ncMuted) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.background(Color.ncCream.ignoresSafeArea()).navigationTitle("Gewohnheiten").navigationBarTitleDisplayMode(.large)
    }
    func calculateStreak() -> Int {
        var s = 0; let cal = Calendar.current
        for i in 0..<365 { guard let day = cal.date(byAdding: .day, value: -i, to: Date()) else { break }; if allLogs.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) { s += 1 } else if i > 0 { break } }
        return s
    }
}

// MARK: - Finance View

struct NAIceFinanceView: View {
    @Query(sort: \Expense.date, order: .reverse) var allExpenses: [Expense]
    @State private var showAdd = false
    private var monthly: [Expense] { allExpenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) } }
    private var monthlyTotal: Double { monthly.reduce(0) { $0 + $1.amount } }
    private var categories: [String: Double] { Dictionary(grouping: monthly, by: { $0.category }).mapValues { $0.reduce(0) { $0 + $1.amount } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) { Text("Finanzen").font(.title2.weight(.bold)).foregroundColor(.ncDark); Text("Tippen fur Budget & Analyse").font(.subheadline).foregroundColor(.ncMuted) }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) { Text("Ausgaben").font(.caption).foregroundColor(.ncMuted); Text("\(Int(monthlyTotal)) Euro").font(.system(size: 30, weight: .bold)).foregroundColor(.ncGreen); Text("diesen Monat").font(.caption2).foregroundColor(.ncSage) }.frame(maxWidth: .infinity, alignment: .leading).padding().warmCard()
                    VStack(alignment: .leading, spacing: 4) { Text("Kategorien").font(.caption).foregroundColor(.ncMuted); Text("\(categories.count)").font(.system(size: 30, weight: .bold)).foregroundColor(.ncDark); Text("aktiv").font(.caption2).foregroundColor(.ncSage) }.frame(maxWidth: .infinity, alignment: .leading).padding().warmCard()
                }
                NAIceCard { HStack { Text("Budget Analyse").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); NAiceSmallButton(label: "Ausgabe") { showAdd = true } }; ForEach(Array(categories.keys.sorted()), id: \.self) { cat in HStack { Text(cat).font(.subheadline).foregroundColor(.ncDark); Spacer(); Text("\(Int(categories[cat]!)) Euro").font(.subheadline.weight(.medium)).foregroundColor(.ncGreen) }.padding(.vertical, 4); Divider().foregroundColor(.ncSand.opacity(0.3)) }; if categories.isEmpty { Text("Noch keine Daten vorhanden.").font(.caption).foregroundColor(.ncSage).padding(.top, 4) } }
                if !allExpenses.isEmpty { NAIceCard { Text("Letzte Ausgaben").font(.headline.weight(.semibold)).foregroundColor(.ncDark); ForEach(Array(allExpenses.prefix(8))) { exp in HStack { Circle().fill(Color.ncSage).frame(width: 6,height: 6); Text(exp.category).font(.subheadline).foregroundColor(.ncDark); Spacer(); Text("\(Int(exp.amount)) Euro").font(.subheadline.weight(.medium)).foregroundColor(.ncGreen) }.padding(.vertical, 2) } } }
                NAIceCard { Text("Tipps").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Lege Kategorien fest, um deine Ausgaben zu organisieren. nAIce hilft dir, Muster zu erkennen.").font(.subheadline).foregroundColor(.ncMuted) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.background(Color.ncCream.ignoresSafeArea()).navigationTitle("Finanzen").navigationBarTitleDisplayMode(.large).sheet(isPresented: $showAdd) { ExpenseFormView() }
    }
}

// MARK: - Expense Form

struct ExpenseFormView: View {
    @Environment(\.modelContext) var mc; @Environment(\.dismiss) var dismiss
    @State private var amount: String = ""; @State private var category: String = ""; @State private var note: String = ""
    let categories = ["Wohnen","Lebensmittel","Transport","Freizeit","Shopping","Gesundheit","Bildung","Sonstiges"]
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Neue Ausgabe").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                HStack { Text("Euro").foregroundColor(.ncMuted); TextField("0.00", text: $amount).keyboardType(.decimalPad).font(.title2.weight(.bold)).foregroundColor(.ncDark).multilineTextAlignment(.trailing) }.padding(14).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())], spacing: 10) { ForEach(categories, id: \.self) { cat in Button { category = cat } label: { Text(cat).font(.subheadline.weight(.medium)).foregroundColor(category == cat ? .white : .ncDark).padding(.horizontal,12).padding(.vertical,8).frame(maxWidth:.infinity).background(category == cat ? Color.ncGreen : Color.ncPaper, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand, lineWidth: 0.5)) } } }
                TextField("Notiz", text: $note).padding(12).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                Button("Speichern") { guard let amt = Double(amount), !category.isEmpty else { return }; mc.insert(Expense(date: Date(), amount: amt, category: category, note: note)); try? mc.save(); dismiss() }.foregroundColor(.white).frame(maxWidth:.infinity).padding(.vertical,14).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14)).opacity((Double(amount) ?? 0) > 0 && !category.isEmpty ? 1 : 0.5).disabled((Double(amount) ?? 0) <= 0 || category.isEmpty)
            }.padding(20).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundColor(.ncMuted) } }
        }
    }
}

// MARK: - More View

struct NAIceMoreView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                NAIceSectionLabel(icon: "briefcase", title: "Arbeiten")
                NavigationLink(destination: NAiceDetailPage(title: "Notizen", icon: "note.text", tips: ["Notizen werden lokal auf deinem Gerat gespeichert.", "Nutze den Agent-Chat, um Notizen durchsuchen zu lassen.", "Tipp: Du kannst Notizen mit #tags versehen."])) { moreRow(icon: "note.text", title: "Notizen", subtitle: "0 gespeichert") }.buttonStyle(PlainButtonStyle())
                NavigationLink(destination: NAiceDetailPage(title: "Posteingang", icon: "tray", tips: ["Der Posteingang sammelt eingehende Nachrichten.", "Ungelesene Nachrichten werden oben angezeigt.", "Antworte direkt oder lasse den Agent antworten."])) { moreRow(icon: "tray", title: "Posteingang", subtitle: "0 ungelesen") }.buttonStyle(PlainButtonStyle())
                NavigationLink(destination: NAiceDetailPage(title: "Automatisierung", icon: "arrow.triangle.branch", tips: ["Wenn X passiert, fuhrt der Agent Y aus.", "Automatisierungen laufen auf dem Server.", "Beispiel: Wenn neue E-Mail, dann Zusammenfassung senden."])) { moreRow(icon: "arrow.triangle.branch", title: "Automatisierung", subtitle: "Wenn X, dann Y") }.buttonStyle(PlainButtonStyle())
                NavigationLink(destination: NAiceDetailPage(title: "Agent Regeln", icon: "bolt.fill", tips: ["Es sind 6 aktive Regeln auf deinem Server.", "Regeln reagieren auf eingehende Daten (Mails, Kalender, etc.).", "Neue Regeln konnen im Server-WebUI erstellt werden."])) { moreRow(icon: "bolt.fill", title: "Agent Regeln", subtitle: "6 aktiv – reagiert auf Daten") }.buttonStyle(PlainButtonStyle())
                NavigationLink(destination: NAiceDetailPage(title: "Server-Workflows", icon: "server.rack", tips: ["Komplexe Automatisierungen kombinieren mehrere Schritte.", "Workflows konnen Trigger, Bedingungen und Aktionen enthalten.", "Beispiel: Termin erkannt → Erinnerung erstellen → Zusammenfassung senden."])) { moreRow(icon: "server.rack", title: "Server-Workflows", subtitle: "Komplexe Automatisierungen") }.buttonStyle(PlainButtonStyle())

                NAIceSectionLabel(icon: "eurosign", title: "Wert & Transparenz")
                NAIceCard { Text("Was kostet nAIce?").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Du brauchst: iOS-Gerat (vorhanden) + Developer Account ($99/J.) + Server (ab $5/Monat). KI-Nutzung via OpenRouter.").font(.subheadline).foregroundColor(.ncMuted).padding(.top, 4) }
                NAIceCard { HStack { VStack(alignment: .leading, spacing: 2) { Text("Zeitersparnis pro Tag").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("ca. 30 Min. – Kein manuelles Planen, Suchen, Erinnern.") }; Spacer(); Image(systemName: "clock").font(.title2).foregroundColor(.ncSage) }.font(.subheadline).foregroundColor(.ncMuted) }
                NAIceCard { HStack { VStack(alignment: .leading, spacing: 2) { Text("Datenschutz").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Gesundheitsdaten bleiben auf dem Gerat. Agent-Daten auf deinem Server. Keine Werbung, kein Tracking.") }; Spacer(); Image(systemName: "lock.shield").font(.title2).foregroundColor(.ncSage) }.font(.subheadline).foregroundColor(.ncMuted) }
                NAIceCard { moreSimpleRow(title: "Verbindungen") }
                NAIceCard { moreSimpleRow(title: "Integrationen") }
                NAIceCard { moreSimpleRow(title: "System") }
                NAIceCard { HStack { VStack(alignment: .leading, spacing: 2) { Text("Einstellungen").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Server, Profil, App").font(.caption).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) } }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.background(Color.ncCream.ignoresSafeArea()).navigationTitle("Mehr").navigationBarTitleDisplayMode(.inline)
    }
    func moreRow(icon: String, title: String, subtitle: String) -> some View {
        NAIceCard { HStack { Image(systemName: icon).font(.title3).foregroundColor(.ncSage).frame(width: 28); VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Text(subtitle).font(.caption).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) } }
    }
    func moreSimpleRow(title: String) -> some View {
        HStack { Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }
    }
}

// MARK: - Warm Card

struct WarmCardModifier: ViewModifier {
    func body(content: Content) -> some View { content.background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ncSand.opacity(0.5), lineWidth: 0.5)).shadow(color: .black.opacity(0.04), radius: 4, y: 1) }
}
extension View { func warmCard() -> some View { modifier(WarmCardModifier()) } }

#Preview { ContentView(authManager: AuthManager()) }