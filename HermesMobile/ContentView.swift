import SwiftUI
import SwiftData
import HealthKit
import EventKit
import Contacts
import CoreLocation

// MARK: - ContentView (Container)
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

// MARK: - HealthKit Manager
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

// MARK: - Calendar Manager
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

// MARK: - Tab View
@MainActor
struct NAIceTabView: View {
    @Bindable var authManager: AuthManager; let server: URL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .home; @State private var ps: SharedImport?; @State private var pd: String?; @State private var pn: NewChatRequest?
    @StateObject private var health = HealthManager.shared; @StateObject private var calendar = CalendarManager.shared; @StateObject private var services = ServiceManager.shared; @StateObject private var rollup = NARollupService.shared; @StateObject private var journal = NAJournalService.shared; @StateObject private var contacts = NAContactService.shared; @StateObject private var waVM = WhatsAppViewModel.shared
    enum Tab: String, CaseIterable { case home; case life; case agent; case whatsapp; case more
        var title: String { switch self { case .home: return "Home"; case .life: return "Leben"; case .agent: return "Agent"; case .whatsapp: return "WhatsApp"; case .more: return "Mehr" } }
        var icon: String { switch self { case .home: return "house"; case .life: return "leaf"; case .agent: return "bubble.left.and.bubble.right"; case .whatsapp: return "message.badge.waveform.fill"; case .more: return "square.grid.2x2" } }
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { AgentHubView(requestedNewChat: $pn) }.tabItem { Label(Tab.home.title, systemImage: Tab.home.icon) }.tag(Tab.home)
            NavigationStack { NAIceLifeView(services: services) }.tabItem { Label(Tab.life.title, systemImage: Tab.life.icon) }.tag(Tab.life)
            SessionListView(authManager: authManager, server: server, pendingSharedImport: $ps, pendingDeepLinkedSessionID: $pd, requestedNewChat: $pn).tabItem { Label(Tab.agent.title, systemImage: Tab.agent.icon) }.tag(Tab.agent)
            NavigationStack { WhatsAppView() }.tabItem { Label(Tab.whatsapp.title, systemImage: Tab.whatsapp.icon) }.badge(waVM.totalUnread > 0 ? waVM.totalUnread : 0).tag(Tab.whatsapp)
            NavigationStack { NAIceMoreView() }.tabItem { Label(Tab.more.title, systemImage: Tab.more.icon) }.tag(Tab.more)
        }.tint(Color.ncGreen).task { await health.requestAuth(); await calendar.requestAuth(); await services.requestAll(); await NAiceAPI.shared.fetchWhoop(); await NAiceAPI.shared.fetchIdeas(); await NARollupService.shared.fetch(); await waVM.fetchPending() }
            .onChange(of: scenePhase, perform: { newPhase in
                guard newPhase == .active else { return }
                Task {
                    await NAiceAPI.shared.fetchWhoop()
                    await NAiceAPI.shared.fetchIdeas()
                    await NARollupService.shared.fetch()
                    await NAJournalService.shared.fetch()
                    if ServiceManager.shared.contactsAuthorized { await NAContactService.shared.fetchContacts() }
                    await NASyncService.shared.syncAll(
                        moods: [],
                        habits: [],
                        expenses: [],
                        health: health,
                        whoop: NAiceAPI.shared.whoop
                    )
                    await waVM.fetchPending()
                }
            })
    }
}

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

#Preview { ContentView(authManager: AuthManager()) }