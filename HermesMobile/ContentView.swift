import SwiftUI
import SwiftData
import HealthKit
import EventKit
import Contacts
import CoreLocation

// MARK: - ContentView (unverändert)
struct ContentView: View {
    @Bindable var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ResponseCompletionNotifications.isEnabledKey) private var isResponseCompletionNotificationsEnabled = false
    @State private var pendingSharedImport: SharedImport?; @State private var pendingDeepLinkedSessionID: String?
    @State private var pendingNewChatRequest: NewChatRequest?; @State private var didCheckInitialPendingShare = false; @State private var intentRouter = AppIntentRouter.shared
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

// MARK: - Colors & Design
extension Color {
    static let ncCream = Color(red: 0.984, green: 0.957, blue: 0.886)
    static let ncPaper = Color(red: 1.0, green: 0.973, blue: 0.906)
    static let ncSand = Color(red: 0.910, green: 0.863, blue: 0.769)
    static let ncSage = Color(red: 0.541, green: 0.608, blue: 0.478)
    static let ncGreen = Color(red: 0.239, green: 0.353, blue: 0.278)
    static let ncGreenLight = Color(red: 0.353, green: 0.478, blue: 0.396)
    static let ncDark = Color(red: 0.102, green: 0.078, blue: 0.051)
    static let ncMuted = Color(red: 0.541, green: 0.510, blue: 0.439)
    static let ncRed = Color(red: 0.761, green: 0.231, blue: 0.231)
    static let ncGold = Color(red: 0.769, green: 0.635, blue: 0.396)
}

struct WarmCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ncSand.opacity(0.4), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
    }
}
extension View {
    func warmCard() -> some View { modifier(WarmCardStyle()) }
    func warmBackground() -> some View { self.background(Color.ncCream.ignoresSafeArea()) }
}

struct NAIceSectionLabel: View {
    let icon: String; let title: String
    var body: some View {
        HStack(spacing: 8) { Image(systemName: icon).font(.caption).foregroundColor(.ncSage); Text(title).font(.caption.weight(.semibold)).foregroundColor(.ncSage).textCase(.uppercase) }
            .padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 8)
    }
}

// MARK: - HealthKit
@MainActor
class HealthManager: ObservableObject {
    static let shared = HealthManager()
    let store = HKHealthStore()
    @Published var steps = 0; @Published var heartRate = 0.0; @Published var hrv = 0.0; @Published var sleepHours = 0.0; @Published var isAuthorized = false
    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types: Set = [HKObjectType.quantityType(forIdentifier: .stepCount)!, HKObjectType.quantityType(forIdentifier: .heartRate)!, HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        do { try await store.requestAuthorization(toShare: [], read: types); isAuthorized = true; await loadAll() } catch { isAuthorized = false }
    }
    func loadAll() async {
        let cal = Calendar.current; let today = cal.startOfDay(for: Date()); let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let p = HKQuery.predicateForSamples(withStart: today, end: tomorrow, options: .strictStartDate)
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in let q = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: p, options: .cumulativeSum) { _, s, _ in c.resume(returning: s?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0) }; self.store.execute(q) }; steps = Int(r ?? 0) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in let q = HKSampleQuery(sampleType: t, predicate: p, limit: 1, sortDescriptors: [.init(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, s, _ in c.resume(returning: (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit(from: "count/min")) ?? 0) }; self.store.execute(q) }; heartRate = r ?? 0 }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in let q = HKSampleQuery(sampleType: t, predicate: p, limit: 1, sortDescriptors: [.init(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, s, _ in c.resume(returning: (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) ?? 0) }; self.store.execute(q) }; hrv = r ?? 0 }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { let r = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Double, Error>) in let q = HKSampleQuery(sampleType: t, predicate: p, limit: 1, sortDescriptors: [.init(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, s, _ in let sec = (s?.first as? HKCategorySample).map { $0.endDate.timeIntervalSince($0.startDate) } ?? 0; c.resume(returning: sec / 3600) }; self.store.execute(q) }; sleepHours = r ?? 0 }
    }
}

// MARK: - Calendar
@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    let store = EKEventStore()
    @Published var todayEvents: [EKEvent] = []; @Published var isAuthorized = false
    func requestAuth() async {
        guard EKEventStore.authorizationStatus(for: .event) != .denied else { return }
        do { if #available(iOS 17, *) { isAuthorized = try await store.requestFullAccessToEvents() } else { isAuthorized = try await store.requestAccess(to: .event) }; if isAuthorized { await loadToday() } } catch { isAuthorized = false }
    }
    func loadToday() async { let cal = Calendar.current; let start = cal.startOfDay(for: Date()); let end = cal.date(byAdding: .day, value: 1, to: start)!; todayEvents = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)) }
}

// MARK: - Service Manager
@MainActor
class ServiceManager: ObservableObject {
    static let shared = ServiceManager()
    let contactStore = CNContactStore(); let locationManager = CLLocationManager(); let reminderStore = EKEventStore()
    @Published var contactsAuthorized = false; @Published var locationAuthorized = false; @Published var remindersAuthorized = false
    func checkStatus() { contactsAuthorized = CNContactStore.authorizationStatus(for: .contacts) == .authorized; locationAuthorized = (locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways); remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .authorized }
    func requestAll() async {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined { do { contactsAuthorized = try await contactStore.requestAccess(for: .contacts) } catch { contactsAuthorized = false } } else { contactsAuthorized = CNContactStore.authorizationStatus(for: .contacts) == .authorized }
        if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }; try? await Task.sleep(nanoseconds: 300_000_000); locationAuthorized = (locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways)
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined { do { if #available(iOS 17, *) { remindersAuthorized = try await reminderStore.requestFullAccessToReminders() } else { remindersAuthorized = try await reminderStore.requestAccess(to: .reminder) } } catch { remindersAuthorized = false } } else { remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .authorized }
    }
}

// MARK: - nAIce Backend API
@MainActor
class NAiceAPI: ObservableObject {
    static let shared = NAiceAPI()
    let base = "https://agent.santoslab.de/api/naice"
    @Published var profile: NAProfile?; @Published var whoop: NAWhoop?; @Published var suggestions: [NASuggestion] = []; @Published var ideas: [NAIdea] = []; @Published var isLoading = false
    func fetchDashboard() async { isLoading = true; guard let url = URL(string: "\(base)/dashboard"), let (data, _) = try? await URLSession.shared.data(from: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { isLoading = false; return }; if let p = json["profile"] as? [String: Any] { profile = NAProfile.from(p) }; if let w = json["whoop"] as? [String: Any] { whoop = NAWhoop.from(w) }; if let ss = json["suggestions"] as? [[String: Any]] { suggestions = ss.compactMap { NASuggestion.from($0) } }; isLoading = false }
    func generateSuggestions() async { guard let url = URL(string: "\(base)/suggestions/generate") else { return }; var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = "{}".data(using: .utf8); guard let (data, _) = try? await URLSession.shared.data(for: r), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let ss = json["suggestions"] as? [[String: Any]] else { return }; suggestions = ss.compactMap { NASuggestion.from($0) } }
    func dismissSuggestion(_ id: String) async { suggestions.removeAll { $0.id == id }; guard let url = URL(string: "\(base)/suggestions/dismiss") else { return }; var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id]); _ = try? await URLSession.shared.data(for: r) }
    func connectWhoop() async { guard let url = URL(string: "\(base)/whoop/connect") else { return }; var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = "{}".data(using: .utf8); guard let (data, _) = try? await URLSession.shared.data(for: r), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let w = json["whoop"] as? [String: Any] else { return }; whoop = NAWhoop.from(w) }
    func addIdea(_ text: String) async { guard let url = URL(string: "\(base)/ideas") else { return }; var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text]); guard let (data, _) = try? await URLSession.shared.data(for: r), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let is_ = json["ideas"] as? [[String: Any]] else { return }; ideas = is_.compactMap { NAIdea.from($0) } }
}
struct NAProfile { let name: String; let role: String; let goals: [String]; let values: [String]; static func from(_ d: [String: Any]) -> NAProfile { NAProfile(name: d["name"] as? String ?? "", role: d["role"] as? String ?? "", goals: d["goals"] as? [String] ?? [], values: d["values"] as? [String] ?? []) } }
struct NAWhoop { let connected: Bool; let recoveryScore: Int; let hrv: Double; let rhr: Int; let strain: Double; let sleepHours: Double; static func from(_ d: [String: Any]) -> NAWhoop { NAWhoop(connected: d["connected"] as? Bool ?? false, recoveryScore: d["recovery_score"] as? Int ?? 0, hrv: d["hrv"] as? Double ?? 0, rhr: d["resting_heart_rate"] as? Int ?? 0, strain: d["strain"] as? Double ?? 0, sleepHours: d["sleep_hours"] as? Double ?? 0) } }
struct NASuggestion: Identifiable { let id: String; let type: String; let title: String; let text: String; let icon: String; let priority: String; var color: Color { priority == "high" ? .ncRed : priority == "medium" ? .ncGold : .ncSage }; static func from(_ d: [String: Any]) -> NASuggestion? { guard let id = d["id"] as? String else { return nil }; return NASuggestion(id: id, type: d["type"] as? String ?? "", title: d["title"] as? String ?? "", text: d["text"] as? String ?? "", icon: d["icon"] as? String ?? "sparkles", priority: d["priority"] as? String ?? "low") } }
struct NAIdea: Identifiable { let id: String; let text: String; let createdAt: Date; static func from(_ d: [String: Any]) -> NAIdea? { guard let id = d["id"] as? String, let text = d["text"] as? String else { return nil }; return NAIdea(id: id, text: text, createdAt: ISO8601DateFormatter().date(from: d["created_at"] as? String ?? "") ?? Date()) } }

// MARK: - Tab View
@MainActor
struct NAIceTabView: View {
    @Bindable var authManager: AuthManager; let server: URL
    @State private var selectedTab: Tab = .home; @State private var ps: SharedImport?; @State private var pd: String?; @State private var pn: NewChatRequest?
    @StateObject private var health = HealthManager.shared; @StateObject private var calendar = CalendarManager.shared; @StateObject private var services = ServiceManager.shared; @StateObject private var naice = NAiceAPI.shared
    enum Tab: String, CaseIterable { case home; case life; case agent; case more
        var title: String { switch self { case .home: return "Home"; case .life: return "Leben"; case .agent: return "Agent"; case .more: return "Mehr" } }
        var icon: String { switch self { case .home: return "house"; case .life: return "leaf"; case .agent: return "bubble.left.and.bubble.right"; case .more: return "square.grid.2x2" } }
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { AgentHubView(health: health, calendar: calendar, services: services, naice: naice) }.tabItem { Label(Tab.home.title, systemImage: Tab.home.icon) }.tag(Tab.home)
            NavigationStack { NAIceLifeView(services: services) }.tabItem { Label(Tab.life.title, systemImage: Tab.life.icon) }.tag(Tab.life)
            SessionListView(authManager: authManager, server: server, pendingSharedImport: $ps, pendingDeepLinkedSessionID: $pd, requestedNewChat: $pn).tabItem { Label(Tab.agent.title, systemImage: Tab.agent.icon) }.tag(Tab.agent)
            NavigationStack { NAIceMoreView() }.tabItem { Label(Tab.more.title, systemImage: Tab.more.icon) }.tag(Tab.more)
        }.tint(Color.ncGreen).task { await health.requestAuth(); await calendar.requestAuth(); await services.requestAll(); await naice.fetchDashboard() }
    }
}

// MARK: - Agent Hub (Home Tab)
struct AgentHubView: View {
    @ObservedObject var health: HealthManager; @ObservedObject var calendar: CalendarManager; @ObservedObject var services: ServiceManager; @ObservedObject var naice: NAiceAPI
    @Query(sort: \MoodEntry.date, order: .reverse) var moods: [MoodEntry]
    @Environment(\.modelContext) var mc
    @State private var showIdea = false; @State private var newIdea = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Greeting
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Circle().fill(Color.ncGreen).frame(width: 48, height: 48).overlay(Image(systemName: "person.fill").font(.title3).foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 2) { Text("Hallo \(naice.profile?.name ?? "Johannes")").font(.headline.weight(.bold)).foregroundColor(.ncDark); Text(timeGreeting()).font(.subheadline).foregroundColor(.ncMuted) }
                        Spacer()
                    }
                    if let w = naice.whoop, w.connected { HStack(spacing: 6) { Circle().fill(Color.ncGreen).frame(width: 8, height: 8); Text("Recovery \(w.recoveryScore)% – Whoop verbunden").font(.caption).foregroundColor(.ncGreen) } }
                    if let m = moods.first { HStack(spacing: 6) { Image(systemName: moodIcon(m.mood)).font(.caption).foregroundColor(moodColor(m.mood)); Text(moodText(m.mood)).font(.caption).foregroundColor(.ncMuted) } }
                }.warmCard()

                // Suggestions
                if !naice.suggestions.isEmpty {
                    NAIceSectionLabel(icon: "sparkles", title: "Dein Agent empfiehlt")
                    ForEach(naice.suggestions) { s in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: s.icon).font(.title3).foregroundColor(s.color).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) { Text(s.title).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Text(s.text).font(.caption).foregroundColor(.ncMuted) }
                            Spacer(minLength: 8)
                            Button { Task { await naice.dismissSuggestion(s.id) } } label: { Image(systemName: "xmark").font(.caption2).foregroundColor(.ncSand) }
                        }.warmCard()
                    }
                }

                // Health
                if health.isAuthorized {
                    NAIceSectionLabel(icon: "heart.fill", title: "Gesundheit")
                    VStack(spacing: 12) {
                        HStack(spacing: 0) { mini("figure.walk", "\(health.steps)", "Schritte"); mini("heart.fill", "\(Int(health.heartRate))", "Puls"); mini("waveform.path.ecg", "\(Int(health.hrv))ms", "HRV"); mini("moon.fill", String(format: "%.1fh", health.sleepHours), "Schlaf") }
                        if let w = naice.whoop, w.connected {
                            HStack(spacing: 12) { whoopMini("arrow.up.heart.fill", "\(w.recoveryScore)%", "Recovery"); whoopMini("heart.fill", "\(w.rhr)", "Ruhepuls"); whoopMini("bolt.fill", String(format: "%.1f", w.strain), "Strain"); whoopMini("moon.zzz.fill", String(format: "%.1fh", w.sleepHours), "Schlaf") }
                        } else { Button("Whoop verbinden") { Task { await naice.connectWhoop() } }.font(.caption.weight(.semibold)).foregroundColor(.ncGreen).padding(.horizontal, 16).padding(.vertical, 8).background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.ncGreen.opacity(0.15))) }
                    }.warmCard()
                }

                // QuickLog
                NAIceSectionLabel(icon: "square.and.pencil", title: "QuickLog & Ideen")
                QuickLogCard(mc: mc)

                if showIdea {
                    HStack(spacing: 8) { TextField("Idee eingeben...", text: $newIdea).padding(10).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand, lineWidth: 0.5)); Button("Speichern") { Task { await naice.addIdea(newIdea); newIdea = ""; showIdea = false } }.font(.caption.weight(.semibold)).foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 9)) }.warmCard()
                } else { Button("Idee festhalten") { showIdea = true }.font(.caption).foregroundColor(.ncSage).padding(.horizontal, 4) }

                ForEach(Array(naice.ideas.prefix(3))) { idea in HStack(spacing: 10) { Image(systemName: "lightbulb.fill").font(.caption).foregroundColor(.ncGold); Text(idea.text).font(.subheadline).foregroundColor(.ncDark); Spacer(); Text(idea.createdAt, style: .relative).font(.caption2).foregroundColor(.ncMuted) }.warmCard() }

                // Tag
                HStack { VStack(alignment: .leading, spacing: 2) { Text("Dein Tag").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text(calendar.todayEvents.isEmpty ? "Keine Termine – Zeit fur deine Projekte" : "\(calendar.todayEvents.count) Termine heute").font(.subheadline).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: calendar.todayEvents.isEmpty ? "sun.max.fill" : "calendar.badge.checkmark").foregroundColor(calendar.todayEvents.isEmpty ? .ncGold : .ncGreen).font(.title2) }.warmCard()

                // Lebensbereiche
                NAIceSectionLabel(icon: "square.grid.2x2", title: "Meine Bereiche")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    area("heart.fill", "Gesundheit", .ncRed, AnyView(HealthDetailView(naice: naice)))
                    area("briefcase.fill", "Arbeit", .ncGreen, AnyView(WorkDetailView()))
                    area("person.2.fill", "Beziehungen", .ncSage, AnyView(RelationsDetailView()))
                    area("lightbulb.fill", "Kreativitat", .ncGold, AnyView(CreativityDetailView(naice: naice)))
                    area("house.fill", "Alltag", .ncDark, AnyView(DailyDetailView()))
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("nAIce").navigationBarTitleDisplayMode(.inline).task { await naice.generateSuggestions() }
    }
    func timeGreeting() -> String { let h = Calendar.current.component(.hour, from: Date()); if h < 6 { return "Nachtruhe?" }; if h < 9 { return "Guten Morgen!" }; if h < 12 { return "Guten Vormittag!" }; if h < 14 { return "Mittagspause?" }; if h < 17 { return "Nachmittag!" }; if h < 21 { return "Feierabend!" }; return "Gute Nacht!" }
    func moodIcon(_ m: String) -> String { m == "good" ? "hand.thumbsup.fill" : m == "neutral" ? "hand.thumbsup" : "hand.thumbsdown" }
    func moodColor(_ m: String) -> Color { m == "good" ? .ncGreen : m == "neutral" ? .ncGold : .ncRed }
    func moodText(_ m: String) -> String { m == "good" ? "Gut gelaunt" : m == "neutral" ? "Neutral" : "Nicht so gut" }
    func mini(_ i: String, _ v: String, _ l: String) -> some View { VStack(spacing: 4) { Image(systemName: i).font(.caption).foregroundColor(.ncSage); Text(v).font(.callout.weight(.bold)).foregroundColor(.ncDark); Text(l).font(.caption2).foregroundColor(.ncMuted) }.frame(maxWidth: .infinity) }
    func whoopMini(_ i: String, _ v: String, _ l: String) -> some View { VStack(spacing: 2) { Image(systemName: i).font(.system(size: 10)).foregroundColor(.ncGreen); Text(v).font(.caption.weight(.bold)).foregroundColor(.ncDark); Text(l).font(.system(size: 8)).foregroundColor(.ncMuted) }.frame(maxWidth: .infinity) }
    func area(_ icon: String, _ title: String, _ color: Color, _ dest: AnyView) -> some View {
        NavigationLink(destination: dest) { VStack(spacing: 8) { Image(systemName: icon).font(.title2).foregroundColor(color); Text(title).font(.caption.weight(.semibold)).foregroundColor(.ncDark) }.frame(maxWidth: .infinity).padding(12).warmCard() }.buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Life View
struct NAIceLifeView: View {
    @ObservedObject var services: ServiceManager
    @Query(sort: \HabitLog.date, order: .reverse) var habits: [HabitLog]; @Query(sort: \Expense.date, order: .reverse) var expenses: [Expense]
    @State private var showHabitLog = false
    var body: some View {
        lifeContent
            .warmBackground()
            .navigationTitle("Leben")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showHabitLog) { HabitLogSheet() }
    }

    @ViewBuilder
    private var lifeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dein Leben").font(.title2.weight(.bold)).foregroundColor(.ncDark).padding(.horizontal, 4).padding(.top, 4)
                HStack(spacing: 12) { Image(systemName: "heart.fill").font(.title2).foregroundColor(.ncGreen); VStack(alignment: .leading, spacing: 2) { Text("Mein Leben").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Tippen fur Details").font(.subheadline).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }.warmCard()
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "lightbulb.fill").font(.title2).foregroundColor(.ncGold); Text("nAIce Insights").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }
                    Text("Verbinde Dienste fur personalisierte Insights.").font(.subheadline).foregroundColor(.ncMuted)
                    HStack(spacing: 6) { naBadge("heart.fill", "Health", HealthManager.shared.isAuthorized); naBadge("calendar", "Kalender", CalendarManager.shared.isAuthorized); naBadge("person.crop.circle", "Kontakte", services.contactsAuthorized); naBadge("location.fill", "Standort", services.locationAuthorized); naBadge("bell.fill", "Reminders", services.remindersAuthorized) }.padding(.top, 4)
                }.warmCard()
                VStack(alignment: .leading, spacing: 10) { Text("Whoop").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Zeigt Recovery Score, HRV, Ruhepuls und Strain.").font(.subheadline).foregroundColor(.ncMuted); HStack { Image(systemName: "heart.circle").font(.title3).foregroundColor(.ncGreen); Text("Whoop verbinden").font(.subheadline.weight(.medium)).foregroundColor(.ncGreen) }.padding(.horizontal, 16).padding(.vertical, 10).background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncGreen.opacity(0.15))) }.warmCard()
                NavigationLink(destination: NAIceHabitsView()) { VStack(alignment: .leading, spacing: 10) { HStack { Text("Gewohnheiten").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }; Text(habits.isEmpty ? "Heute noch nichts geloggt" : "\(habits.filter { Calendar.current.isDateInToday($0.date) }.count) heute geloggt").font(.subheadline).foregroundColor(.ncMuted); HStack(spacing: 10) { Image(systemName: "figure.walk").font(.title3).foregroundColor(.ncSage); VStack(alignment: .leading, spacing: 1) { Text("Heutige Challenge:").font(.caption).foregroundColor(.ncMuted); Text("Gehe 15 Min Spazieren").font(.subheadline.weight(.medium)).foregroundColor(.ncDark) }; Spacer(); Button("Loggen") { showHabitLog = true }.font(.caption.weight(.semibold)).foregroundColor(.ncGreen).padding(.horizontal, 14).padding(.vertical, 7).background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.ncGreen.opacity(0.15))) } } }.warmCard() }.buttonStyle(PlainButtonStyle())
                NavigationLink(destination: NAIceFinanceView()) { VStack(alignment: .leading, spacing: 10) { HStack { VStack(alignment: .leading, spacing: 2) { Text("Finanzen").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Tippen fur Budget & Analyse").font(.caption).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }; let monthly = expenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }; HStack(spacing: 24) { VStack(alignment: .leading, spacing: 2) { Text("Ausgaben").font(.caption).foregroundColor(.ncMuted); Text("\(Int(monthly.reduce(0) { $0 + $1.amount })) Euro").font(.title3.weight(.bold)).foregroundColor(.ncGreen) }; Divider().frame(height: 30); VStack(alignment: .leading, spacing: 2) { Text("Kategorien").font(.caption).foregroundColor(.ncMuted); Text("\(Set(monthly.map { $0.category }).count)").font(.title3.weight(.bold)).foregroundColor(.ncDark) } } }.warmCard() }.buttonStyle(PlainButtonStyle())
                VStack(alignment: .leading, spacing: 12) { HStack { Text("Menschen").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }; Text("Keine Geburtstage in den nachsten 14 Tagen.").font(.subheadline).foregroundColor(.ncMuted); VStack(spacing: 8) { contactRow("Jochen Rupp", "J"); Divider().foregroundColor(.ncSand.opacity(0.3)); contactRow("Martin Grassl", "M") } }.warmCard()
                VStack(alignment: .leading, spacing: 10) { HStack { Text("Apple Daten").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "checkmark.circle.fill").foregroundColor(.ncGreen).font(.title3) }; Text("Alles aktuell – keine anstehenden Termine oder Aufgaben.").font(.subheadline).foregroundColor(.ncMuted); HStack(spacing: 6) { naBadge("calendar", "Kalender", CalendarManager.shared.isAuthorized); naBadge("bell.fill", "Erinnerungen", services.remindersAuthorized); naBadge("location.fill", "Standort", services.locationAuthorized); naBadge("person.crop.circle", "Kontakte", services.contactsAuthorized); naBadge("note.text", "Notizen", false) }.padding(.top, 4) }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
    }
    func naBadge(_ icon: String, _ label: String, _ connected: Bool) -> some View { HStack(spacing: 4) { Image(systemName: icon).font(.system(size: 8)); Text(label).font(.system(size: 9)) }.foregroundColor(connected ? .ncGreen : .ncSand).padding(.horizontal, 8).padding(.vertical, 4).background((connected ? Color.ncGreen : Color.ncSand).opacity(0.1), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke((connected ? Color.ncGreen : Color.ncSand).opacity(0.2), lineWidth: 0.5)) }
    func contactRow(_ name: String, _ initial: String) -> some View { HStack(spacing: 12) { ZStack { Circle().fill(Color.ncSage.opacity(0.2)).frame(width: 34, height: 34); Text(initial).font(.subheadline.weight(.bold)).foregroundColor(.ncDark) }; Text(name).font(.subheadline).foregroundColor(.ncDark); Spacer(); Button("Kontakt auffrischen?") { }.font(.caption).foregroundColor(.ncGreen) } }

// MARK: - QuickLog
struct QuickLogCard: View {
    let mc: ModelContext; @State private var showMood = false; @State private var showHabit = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("QUICKLOG").font(.caption.weight(.semibold)).foregroundColor(.ncSage); Spacer(); Button { showMood = true } label: { Image(systemName: "face.smiling").foregroundColor(.ncSage) }; Button { showHabit = true } label: { Image(systemName: "plus.circle").foregroundColor(.ncSage) } }
            if !showMood && !showHabit { Text("Schnell erfassen: Wie fuhlst du dich oder was hast du gemacht?").font(.subheadline).foregroundColor(.ncMuted) }
            if showMood { HStack(spacing: 24) { qm("good", "\u{1F60A}", "Gut"); qm("neutral", "\u{1F610}", "Neutral"); qm("bad", "\u{1F614}", "Nicht gut"); Button("X") { showMood = false }.font(.caption).foregroundColor(.ncSand) } }
            if showHabit { HStack(spacing: 16) { qh("walk","figure.walk"); qh("water","drop.fill"); qh("reading","book.fill"); qh("workout","dumbbell.fill"); qh("meditation","brain.head.profile"); Button("X") { showHabit = false }.font(.caption).foregroundColor(.ncSand) } }
        }.warmCard()
    }
    func qm(_ m: String, _ e: String, _ l: String) -> some View { Button { mc.insert(MoodEntry(date: Date(), mood: m, note: "")); try? mc.save(); showMood = false } label: { VStack(spacing: 4) { Text(e).font(.title2); Text(l).font(.caption2).foregroundColor(.ncMuted) } } }
    func qh(_ h: String, _ i: String) -> some View { Button { mc.insert(HabitLog(date: Date(), habit: h, isCompleted: true, note: "")); try? mc.save(); showHabit = false } label: { Image(systemName: i).font(.title3).foregroundColor(.ncSage).frame(width: 36, height: 36).background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) } }
}

// MARK: - Mood View
struct NAIceMoodView: View {
    @Environment(\.modelContext) var mc; @Environment(\.dismiss) var dismiss
    @Query(sort: \MoodEntry.date, order: .reverse) var moods: [MoodEntry]
    @State private var selectedMood = "good"; @State private var note = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Wie fuhlst du dich?").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                HStack(spacing: 24) { moodButton("good","\u{1F60A}","Gut"); moodButton("neutral","\u{1F610}","Neutral"); moodButton("bad","\u{1F614}","Nicht gut") }
                TextField("Notiz (optional)", text: $note).padding(14).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                Button("Eintragen") { mc.insert(MoodEntry(date: Date(), mood: selectedMood, note: note)); try? mc.save(); dismiss() }.font(.headline.weight(.semibold)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14))
                if !moods.isEmpty { NAIceSectionLabel(icon: "clock", title: "Verlauf"); ForEach(Array(moods.prefix(14))) { entry in HStack(spacing: 14) { Text(moodEmoji(entry.mood)).font(.title3); VStack(alignment: .leading, spacing: 2) { Text(moodText(entry.mood)).font(.subheadline.weight(.medium)).foregroundColor(.ncDark); Text(entry.date, style: .date).font(.caption).foregroundColor(.ncMuted) }; Spacer(); if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundColor(.ncMuted).lineLimit(1) } }.warmCard() } }
            }.padding(20)
        }.warmBackground().navigationTitle("Mood").navigationBarTitleDisplayMode(.inline)
    }
    func moodButton(_ m: String, _ e: String, _ l: String) -> some View { Button { selectedMood = m } label: { VStack(spacing: 8) { Text(e).font(.system(size: 40)); Text(l).font(.caption).foregroundColor(.ncMuted) }.padding(16).background(RoundedRectangle(cornerRadius: 14).fill(selectedMood == m ? Color.ncGreen.opacity(0.08) : Color.ncPaper)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedMood == m ? Color.ncGreen : Color.ncSand, lineWidth: selectedMood == m ? 1.5 : 0.5)) } }
    func moodEmoji(_ m: String) -> String { m == "good" ? "\u{1F60A}" : m == "neutral" ? "\u{1F610}" : "\u{1F614}" }
    func moodText(_ m: String) -> String { m == "good" ? "Gut" : m == "neutral" ? "Neutral" : "Nicht gut" }
}

// MARK: - Detail Views (Gesundheit, Arbeit, Beziehungen, Kreativität, Alltag)
struct HealthDetailView: View {
    @ObservedObject var naice: NAiceAPI; @ObservedObject var health = HealthManager.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Gesundheit").font(.title2.weight(.bold)).foregroundColor(.ncDark); Text("Deine Vitaldaten auf einen Blick.").font(.subheadline).foregroundColor(.ncMuted)
                if !(naice.whoop?.connected ?? false) { Button("Whoop verbinden") { Task { await naice.connectWhoop() } }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14)) }
                if let w = naice.whoop, w.connected { VStack(spacing: 12) { HStack { Text("Whoop Recovery").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Text("\(w.recoveryScore)%").font(.largeTitle.weight(.bold)).foregroundColor(w.recoveryScore > 60 ? .ncGreen : .ncRed) }; ProgressView(value: Double(w.recoveryScore) / 100).tint(w.recoveryScore > 60 ? .ncGreen : .ncRed); Divider(); hRow("HRV", "\(Int(w.hrv)) ms"); hRow("Ruhepuls", "\(w.rhr) bpm"); hRow("Strain", String(format: "%.1f", w.strain)); hRow("Schlaf", String(format: "%.1f h", w.sleepHours)) }.warmCard() }
                if health.isAuthorized { VStack(spacing: 10) { Text("HealthKit").font(.headline.weight(.semibold)).foregroundColor(.ncDark); hRow("Schritte", "\(health.steps)"); hRow("Puls", "\(Int(health.heartRate)) bpm"); hRow("HRV", "\(Int(health.hrv)) ms"); hRow("Schlaf", String(format: "%.1f h", health.sleepHours)) }.warmCard() }
                VStack(spacing: 8) { Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Deine HRV und Schlafdaten geben Aufschluss uber deine Erholung. Ein Recovery Score uber 60% bedeutet, dass dein Korper bereit fur Belastung ist.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
                VStack(spacing: 8) { Text("Whoop API Echtzeitdaten").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Der Whoop-Server liefert deine aktuellen Vitaldaten automatisch. Recovery, HRV, Schlaf und Strain werden mit jeder Aktualisierung synchronisiert.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Gesundheit").navigationBarTitleDisplayMode(.large)
    }
    func hRow(_ t: String, _ v: String) -> some View { HStack { Text(t).font(.subheadline).foregroundColor(.ncDark); Spacer(); Text(v).font(.subheadline.weight(.bold)).foregroundColor(.ncDark) }.padding(.vertical, 2) }
}

struct WorkDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Arbeit").font(.title2.weight(.bold)).foregroundColor(.ncDark); Text("Deine Produktivitat im Uberblick.").font(.subheadline).foregroundColor(.ncMuted)
                wCard("Chat Sessions", "Dein Hermes Agent ist bereit. Offne den Agent-Tab fur Sessions und Chats.", "bubble.left.and.bubble.right")
                wCard("Notizen", "Erfasse und organisiere Gedanken. Der Agent fasst zusammen.", "note.text")
                wCard("Proaktive Zusammenfassung", "Dein Agent kann regelmassig Zusammenfassungen deiner Chats und Notizen erstellen und dir Vorschlage unterbreiten.", "text.bubble.fill")
                wCard("Aufgaben & Fokus", "Der Agent merkt sich deine Arbeitszeiten. Er schlagt optimale Fenster fur tiefe Arbeit vor.", "brain.head.profile")
                VStack(spacing: 8) { Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Deine produktivste Zeit ist am Vormittag. Plane wichtige Aufgaben zwischen 9 und 12 Uhr.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Arbeit").navigationBarTitleDisplayMode(.large)
    }
    func wCard(_ t: String, _ txt: String, _ i: String) -> some View { HStack(spacing: 12) { Image(systemName: i).font(.title2).foregroundColor(.ncSage).frame(width: 30); VStack(alignment: .leading, spacing: 2) { Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Text(txt).font(.caption).foregroundColor(.ncMuted) } }.warmCard() }
}

struct RelationsDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Beziehungen").font(.title2.weight(.bold)).foregroundColor(.ncDark); Text("Deine Kontakte und Verbindungen.").font(.subheadline).foregroundColor(.ncMuted)
                rCard("Geburtstage", "Keine Geburtstage in den nachsten 14 Tagen – ruhige Phase.", "star.fill")
                rCard("Jochen Rupp", "Zuletzt aktualisiert vor 3 Monaten. Vorschlag: Kurze Nachricht.", "person.crop.circle")
                rCard("Martin Grassl", "Zuletzt aktualisiert vor 2 Monaten. Vorschlag: Kaffee einladen.", "person.crop.circle")
                rCard("Familie", "Regelmaiger Kontakt starkt Bindungen. Dein Agent erinnert an Geburtstage und Anlasse.", "house.fill")
                VStack(spacing: 8) { Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Einmal pro Woche eine kurze Nachricht an einen Kontakt kann Beziehungen starken. Dein Agent erinnert dich.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Beziehungen").navigationBarTitleDisplayMode(.large)
    }
    func rCard(_ t: String, _ txt: String, _ i: String) -> some View { HStack(spacing: 12) { Image(systemName: i).font(.title2).foregroundColor(.ncSage).frame(width: 28); VStack(alignment: .leading, spacing: 2) { Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Text(txt).font(.caption).foregroundColor(.ncMuted) } }.warmCard() }
}

struct CreativityDetailView: View {
    @ObservedObject var naice: NAiceAPI; @State private var newIdea = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Kreativitat").font(.title2.weight(.bold)).foregroundColor(.ncDark); Text("Sammle und entwickle Ideen mit deinem Agent.").font(.subheadline).foregroundColor(.ncMuted)
                HStack(spacing: 8) { TextField("Neue Idee...", text: $newIdea).padding(10).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand)); Button("Speichern") { Task { let i = newIdea; newIdea = ""; await naice.addIdea(i) } }.font(.caption.weight(.semibold)).foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 9)) }
                if naice.ideas.isEmpty { Text("Noch keine Ideen gespeichert. Leg los!").font(.subheadline).foregroundColor(.ncMuted) }
                ForEach(naice.ideas) { idea in HStack(spacing: 12) { Image(systemName: "lightbulb.fill").font(.title3).foregroundColor(.ncGold); VStack(alignment: .leading, spacing: 2) { Text(idea.text).font(.subheadline).foregroundColor(.ncDark); Text(idea.createdAt, style: .date).font(.caption).foregroundColor(.ncMuted) }; Spacer() }.warmCard() }
                cCard("Brainstorming-Partner", "Dein Agent kann mit dir zusammen Ideen entwickeln, erweitern und strukturieren. Einfach im Chat starten.")
                cCard("Kreativ-Routinen", "Die besten Ideen kommen beim Spazierengehen oder unter der Dusche. Halte sie sofort fest – dein nAIce Agent speichert fur dich.", "brain.head.profile")
                VStack(spacing: 8) { Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Setze dir ein Ziel: 3 Ideen pro Woche. Dein Agent hilft dir, sie zu sortieren und weiterzuentwickeln.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Kreativitat").navigationBarTitleDisplayMode(.large)
    }
    func cCard(_ t: String, _ txt: String, _ i: String = "lightbulb") -> some View { HStack(spacing: 12) { Image(systemName: i).font(.title2).foregroundColor(.ncGold).frame(width: 28); VStack(alignment: .leading, spacing: 2) { Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Text(txt).font(.caption).foregroundColor(.ncMuted) } }.warmCard() }
}

struct DailyDetailView: View {
    @ObservedObject var calendar = CalendarManager.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Alltag").font(.title2.weight(.bold)).foregroundColor(.ncDark); Text("Dein Tagesablauf im Griff.").font(.subheadline).foregroundColor(.ncMuted)
                HStack { VStack(alignment: .leading, spacing: 2) { Text(calendar.todayEvents.isEmpty ? "Keine Termine heute" : "\(calendar.todayEvents.count) Termine heute").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Standort: Dietmannsried – sonnig, 22°C").font(.subheadline).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: "sun.max.fill").font(.title2).foregroundColor(.ncGold) }.warmCard()
                dCard("Morgendlicher Check-in", "Dein Agent begrusst dich mit Wetter, Terminen und Health-Daten. Jeden Morgen – bevor du fragst.")
                dCard("Standort-basierte Erinnerungen", "Wenn du nach Hause kommst: Erinnerung an Einkaufe. Wenn du das Buro verlassen hast: Chat-Zusammenfassung.")
                dCard("Abendliche Reflexion", "Was war gut heute? Was morgen besser? Der Agent lernt aus deinen Antworten.")
                dCard("Routinen & Gewohnheiten", "Dein Agent erkennt Muster in deinem Tag und schlagt Optimierungen vor." )
                VStack(spacing: 8) { Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Routinen geben Struktur, aber Flexibilitat macht glucklich. Dein nAIce Agent lernt, wann du Struktur brauchst und wann Freiheit.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Alltag").navigationBarTitleDisplayMode(.large)
    }
    func dCard(_ t: String, _ txt: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Text(txt).font(.caption).foregroundColor(.ncMuted) }.warmCard() }
}

// MARK: - Habits Detail
struct NAIceHabitsView: View {
    @Query(sort: \HabitLog.date, order: .reverse) var allLogs: [HabitLog]
    private var thisWeek: [HabitLog] { let cal = Calendar.current; let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!; return allLogs.filter { $0.date >= start } }
    private let challenges = ["Gehe 15 Min Spazieren","Trinke 2L Wasser","10 Min Meditieren","20 Min Lesen","5 Min Tagebuch","Dehnubungen 10 Min"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) { HStack { Image(systemName: "star.fill").font(.title2).foregroundColor(.ncGold); Text("Heutige Challenge").font(.headline.weight(.semibold)).foregroundColor(.ncDark) }; Text(challenges[Calendar.current.component(.day, from: Date()) % challenges.count]).font(.body.weight(.medium)).foregroundColor(.ncDark); Text("Diese Challenge wurde fur dich ausgewahlt.").font(.caption).foregroundColor(.ncMuted) }.warmCard()
                VStack(alignment: .leading, spacing: 10) { Text("Wochen-Ruckblick").font(.headline.weight(.semibold)).foregroundColor(.ncDark); if thisWeek.isEmpty { Text("Diese Woche noch keine Gewohnheiten geloggt. Starte heute! \u{1F4AA}").font(.subheadline).foregroundColor(.ncMuted) }; let days = ["Mo","Di","Mi","Do","Fr","Sa","So"]; VStack(spacing: 0) { ForEach(Array(days.enumerated()), id: \.offset) { idx, day in let dd = Calendar.current.date(byAdding: .day, value: idx - Calendar.current.component(.weekday, from: Date()) + 1, to: Date()) ?? Date(); let c = thisWeek.filter { Calendar.current.isDate($0.date, inSameDayAs: dd) }.count; HStack(spacing: 12) { Text(day).font(.subheadline.weight(.medium)).foregroundColor(.ncMuted).frame(width: 28, alignment: .leading); RoundedRectangle(cornerRadius: 4).fill(c > 0 ? Color.ncGreen : Color.ncSand.opacity(0.3)).frame(height: 18); Text("\(c)").font(.caption).foregroundColor(.ncMuted).frame(width: 20) }.padding(.vertical, 6); if idx < 6 { Divider().foregroundColor(.ncSand.opacity(0.3)) } } }; let pct = Double(thisWeek.count) / Double(days.count * 3) * 100; ProgressView(value: min(pct / 100, 1)).tint(.ncGreen); Text("\(Int(min(pct, 100))) % abgeschlossen").font(.caption).foregroundColor(.ncMuted) }.warmCard()
                let streak = calculateStreak()
                VStack(alignment: .leading, spacing: 8) { HStack { Image(systemName: "flame.fill").font(.title2).foregroundColor(.ncGold); Text("Serie").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Text("\(streak) Tage").font(.title2.weight(.bold)).foregroundColor(.ncGreen) }; Text(streak > 0 ? "Weiter so! \u{1F44F}" : "Starte heute deine Serie!").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Gewohnheiten").navigationBarTitleDisplayMode(.large)
    }
    func calculateStreak() -> Int { var s = 0; let cal = Calendar.current; for i in 0..<365 { guard let day = cal.date(byAdding: .day, value: -i, to: Date()) else { break }; if allLogs.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) { s += 1 } else if i > 0 { break } }; return s }
}

// MARK: - Finance View
struct NAIceFinanceView: View {
    @Query(sort: \Expense.date, order: .reverse) var all: [Expense]; @State private var showAdd = false
    private var m: [Expense] { all.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) } }
    private var total: Double { m.reduce(0) { $0 + $1.amount } }
    private var cats: [String: Double] { Dictionary(grouping: m, by: { $0.category }).mapValues { $0.reduce(0) { $0 + $1.amount } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) { Text("Finanzen").font(.title2.weight(.bold)).foregroundColor(.ncDark); Text("Tippen fur Budget & Analyse").font(.subheadline).foregroundColor(.ncMuted) }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) { Text("Ausgaben").font(.caption).foregroundColor(.ncMuted); Text("\(Int(total)) Euro").font(.system(size: 28, weight: .bold)).foregroundColor(.ncGreen); Text("diesen Monat").font(.caption2).foregroundColor(.ncSage) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).warmCard()
                    VStack(alignment: .leading, spacing: 4) { Text("Kategorien").font(.caption).foregroundColor(.ncMuted); Text("\(cats.count)").font(.system(size: 28, weight: .bold)).foregroundColor(.ncDark); Text("aktiv").font(.caption2).foregroundColor(.ncSage) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).warmCard()
                }
                VStack(alignment: .leading, spacing: 10) { HStack { Text("Budget Analyse").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Button("Ausgabe") { showAdd = true }.font(.caption.weight(.semibold)).foregroundColor(.ncGreen).padding(.horizontal, 14).padding(.vertical, 7).background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.ncGreen.opacity(0.15))) }; ForEach(Array(cats.keys.sorted()), id: \.self) { cat in HStack { Text(cat).font(.subheadline).foregroundColor(.ncDark); Spacer(); Text("\(Int(cats[cat]!)) Euro").font(.subheadline.weight(.medium)).foregroundColor(.ncGreen) }.padding(.vertical, 4); Divider().foregroundColor(.ncSand.opacity(0.3)) }; if cats.isEmpty { Text("Noch keine Daten.").font(.caption).foregroundColor(.ncSage).padding(.top, 4) } }.warmCard()
                if !all.isEmpty { VStack(alignment: .leading, spacing: 8) { Text("Letzte Ausgaben").font(.headline.weight(.semibold)).foregroundColor(.ncDark); ForEach(Array(all.prefix(8))) { e in HStack { Circle().fill(Color.ncSage).frame(width: 6, height: 6); Text(e.category).font(.subheadline).foregroundColor(.ncDark); Spacer(); Text("\(Int(e.amount)) Euro").font(.subheadline.weight(.medium)).foregroundColor(.ncGreen) }.padding(.vertical, 3) } }.warmCard() }
                VStack(alignment: .leading, spacing: 8) { Text("Tipps").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Kategorien helfen, Muster zu erkennen. nAIce analysiert deine Ausgaben.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Finanzen").navigationBarTitleDisplayMode(.large).sheet(isPresented: $showAdd) { ExpenseFormView() }
    }
}

// MARK: - Expense Form
struct ExpenseFormView: View {
    @Environment(\.modelContext) var mc; @Environment(\.dismiss) var dismiss
    @State private var amount = ""; @State private var category = ""; @State private var note = ""
    let cats = ["Wohnen","Lebensmittel","Transport","Freizeit","Shopping","Gesundheit","Bildung","Sonstiges"]
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Neue Ausgabe").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                HStack { Text("Euro").foregroundColor(.ncMuted); TextField("0.00", text: $amount).keyboardType(.decimalPad).font(.title2.weight(.bold)).foregroundColor(.ncDark).multilineTextAlignment(.trailing) }.padding(14).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { ForEach(cats, id: \.self) { cat in Button { category = cat } label: { Text(cat).font(.subheadline.weight(.medium)).foregroundColor(category == cat ? .white : .ncDark).padding(.horizontal,12).padding(.vertical,8).frame(maxWidth:.infinity).background(category == cat ? Color.ncGreen : Color.ncPaper, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand, lineWidth: 0.5)) } } }
                TextField("Notiz", text: $note).padding(14).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                Button("Speichern") { guard let a = Double(amount), !category.isEmpty else { return }; mc.insert(Expense(date: Date(), amount: a, category: category, note: note)); try? mc.save(); dismiss() }.font(.headline.weight(.semibold)).foregroundColor(.white).frame(maxWidth:.infinity).padding(.vertical,14).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14)).opacity((Double(amount) ?? 0) > 0 && !category.isEmpty ? 1 : 0.5).disabled((Double(amount) ?? 0) <= 0 || category.isEmpty)
            }.padding(24).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundColor(.ncMuted) } }
        }
    }
}

// MARK: - Habit Log Sheet
struct HabitLogSheet: View {
    @Environment(\.modelContext) var mc; @Environment(\.dismiss) var dismiss
    @State private var selected = "walk"; @State private var note = ""
    let opts = [("walk","figure.walk","Spazieren"),("water","drop.fill","Wasser"),("reading","book.fill","Lesen"),("workout","dumbbell.fill","Training"),("meditation","brain.head.profile","Meditation")]
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Gewohnheit loggen").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())], spacing: 14) { ForEach(opts, id: \.0) { o in Button { selected = o.0 } label: { VStack(spacing: 8) { Image(systemName: o.1).font(.title2).foregroundColor(selected == o.0 ? .white : .ncSage).frame(width: 40,height: 40).background(selected == o.0 ? Color.ncGreen : Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)); Text(o.2).font(.caption).foregroundColor(.ncDark) }.padding(12).frame(maxWidth:.infinity).background(RoundedRectangle(cornerRadius: 14).fill(Color.ncPaper)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == o.0 ? Color.ncGreen : Color.ncSand, lineWidth: selected == o.0 ? 1.5 : 0.5)) } } }
                TextField("Notiz (optional)", text: $note).padding(14).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand, lineWidth: 0.5))
                Button("Loggen") { mc.insert(HabitLog(date: Date(), habit: selected, isCompleted: true, note: note)); try? mc.save(); dismiss() }.font(.headline.weight(.semibold)).foregroundColor(.white).frame(maxWidth:.infinity).padding(.vertical,14).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14))
            }.padding(24).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundColor(.ncMuted) } }
        }
    }
}

// MARK: - More View
struct NAIceMoreView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                NAIceSectionLabel(icon: "briefcase", title: "Arbeiten")
                moreR("note.text","Notizen","0 gespeichert"); moreR("tray","Posteingang","0 ungelesen"); moreR("arrow.triangle.branch","Automatisierung","Wenn X, dann Y"); moreR("bolt.fill","Agent Regeln","6 aktiv – reagiert auf Daten"); moreR("server.rack","Server-Workflows","Komplexe Automatisierungen")
                NAIceSectionLabel(icon: "eurosign", title: "Wert & Transparenz")
                VStack(alignment: .leading, spacing: 8) { Text("Was kostet nAIce?").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("iOS-Gerat + Developer Account ($99/J.) + Server (ab $5/Monat). KI via OpenRouter.").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
                HStack { VStack(alignment: .leading, spacing: 2) { Text("Zeitersparnis pro Tag").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("ca. 30 Min – Kein manuelles Planen.") }; Spacer(); Image(systemName: "clock").font(.title2).foregroundColor(.ncSage) }.font(.subheadline).foregroundColor(.ncMuted).warmCard()
                HStack { VStack(alignment: .leading, spacing: 2) { Text("Datenschutz").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Gesundheitsdaten bleiben auf dem Gerat. Keine Werbung.") }; Spacer(); Image(systemName: "lock.shield").font(.title2).foregroundColor(.ncSage) }.font(.subheadline).foregroundColor(.ncMuted).warmCard()
                moreS("Verbindungen"); moreS("Integrationen"); moreS("System")
                HStack { VStack(alignment: .leading, spacing: 2) { Text("Einstellungen").font(.headline.weight(.semibold)).foregroundColor(.ncDark); Text("Server, Profil, App") }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }.warmCard()
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.warmBackground().navigationTitle("Mehr").navigationBarTitleDisplayMode(.inline)
    }
    func moreR(_ i: String, _ t: String, _ s: String) -> some View { HStack { Image(systemName: i).font(.title3).foregroundColor(.ncSage).frame(width: 28); VStack(alignment: .leading, spacing: 2) { Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Text(s).font(.caption).foregroundColor(.ncMuted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }.warmCard() }
    func moreS(_ t: String) -> some View { HStack { Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand) }.warmCard() }
}

#Preview { ContentView(authManager: AuthManager()) }