import SwiftUI

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
        content
            .onOpenURL(perform: handleOpenURL)
            .task {
                guard !didCheckInitialPendingShare else { return }
                didCheckInitialPendingShare = true
                importPendingSharedDraftIfAvailable()
                drainPendingIntentDeepLink()
            }
            .onChange(of: intentRouter.pendingDeepLink) {
                drainPendingIntentDeepLink()
            }
            .task {
                await reconcileOrphanedLiveActivities(notifiesOnCompletion: true)
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                importPendingSharedDraftIfAvailable()
                Task { await reconcileOrphanedLiveActivities(notifiesOnCompletion: false) }
            }
    }

    private func reconcileOrphanedLiveActivities(notifiesOnCompletion: Bool) async {
        guard case let .loggedIn(server) = authManager.state else { return }
        await LiveActivityReconciler.reconcileOrphanedActivities(
            server: server,
            notifiesOnCompletion: notifiesOnCompletion,
            preferenceEnabled: isResponseCompletionNotificationsEnabled
        )
    }

    @ViewBuilder
    private var content: some View {
        switch authManager.state {
        case .unconfigured:
            OnboardingView(authManager: authManager)
        case .loggedOut(let server):
            OnboardingView(authManager: authManager, savedServer: server)
        case .loggedIn(let server):
            NAIceTabView(
                authManager: authManager,
                server: server
            )
            .id(server)
        }
    }

    private func handleOpenURL(_ url: URL) {
        if HermesDeepLink.isNewChatVoiceURL(url) {
            pendingNewChatRequest = NewChatRequest(autoStartsVoiceInput: true)
            return
        }
        if HermesDeepLink.isNewChatInProfileURL(url) {
            pendingNewChatRequest = NewChatRequest(
                profileName: HermesDeepLink.profileName(fromNewChatInProfile: url)
            )
            return
        }
        if HermesDeepLink.isNewChatURL(url) {
            pendingNewChatRequest = NewChatRequest(autoStartsVoiceInput: false)
            return
        }
        if let sessionID = HermesDeepLink.sessionID(from: url) {
            pendingDeepLinkedSessionID = sessionID
            return
        }
        guard HermesShareDraft.isShareOpenURL(url) else { return }
        importPendingSharedDraftIfAvailable()
    }

    private func drainPendingIntentDeepLink() {
        guard let url = intentRouter.pendingDeepLink else { return }
        intentRouter.pendingDeepLink = nil
        handleOpenURL(url)
    }

    private func importPendingSharedDraftIfAvailable() {
        guard let directory = HermesShareDraft.containerURL() else { return }
        do {
            if let sharedImport = try HermesShareDraft.loadPendingImport(from: directory) {
                pendingSharedImport = sharedImport
            }
        } catch {
            pendingSharedImport = nil
        }
    }
}

// MARK: - nAIce Color Palette

extension Color {
    static let naiceCream = Color(hexRGB: "#FBF4E2")!
    static let naiceWarmPaper = Color(hexRGB: "#FFF8E7")!
    static let naiceWarmSand = Color(hexRGB: "#E8DCC4")!
    static let naiceSage = Color(hexRGB: "#8A9B7A")!
    static let naiceGreen = Color(hexRGB: "#3D5A47")!
    static let naiceGreenLight = Color(hexRGB: "#5A7A65")!
    static let naiceDark = Color(hexRGB: "#1A140D")!
    static let naiceMuted = Color(hexRGB: "#8A8270")!
    static let naiceRed = Color(hexRGB: "#C23B3B")!
    static let naiceGold = Color(hexRGB: "#C4A265")!
}

// MARK: - nAIce Design Helpers

struct WarmCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.naiceWarmPaper)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.naiceWarmSand.opacity(0.6), lineWidth: 1))
            .shadow(color: Color.naiceDark.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func warmCard() -> some View { modifier(WarmCardModifier()) }
    func warmBackground() -> some View { background(Color.naiceCream.ignoresSafeArea()) }
}

struct NAiceSectionHeader: View {
    let icon: String; let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.body).foregroundColor(.naiceSage)
            Text(title).font(.title2.weight(.bold)).foregroundColor(.naiceDark)
        }.padding(.top, 8).padding(.bottom, 2)
    }
}

struct NAiceBadge: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}

struct NAIceCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - nAIce Tab View

@MainActor
struct NAIceTabView: View {
    @Bindable var authManager: AuthManager
    let server: URL
    @State private var selectedTab: Tab = .home
    @State private var pendingSharedImport: SharedImport?
    @State private var pendingDeepLinkedSessionID: String?
    @State private var pendingNewChat: NewChatRequest?
    
    enum Tab: String, CaseIterable {
        case home; case life; case agent; case more
        var title: String {
            switch self {
            case .home: return "Home"; case .life: return "Leben"
            case .agent: return "Agent"; case .more: return "Mehr"
            }
        }
        var icon: String {
            switch self {
            case .home: return "house"; case .life: return "leaf"
            case .agent: return "bubble.left.and.bubble.right"; case .more: return "square.grid.2x2"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { NAIceHomeView() }
                .tabItem { Label(Tab.home.title, systemImage: Tab.home.icon) }
                .tag(Tab.home)
            NavigationStack { NAIceLifeView() }
                .tabItem { Label(Tab.life.title, systemImage: Tab.life.icon) }
                .tag(Tab.life)
            SessionListView(
                authManager: authManager, server: server,
                pendingSharedImport: $pendingSharedImport,
                pendingDeepLinkedSessionID: $pendingDeepLinkedSessionID,
                requestedNewChat: $pendingNewChat
            ).tabItem { Label(Tab.agent.title, systemImage: Tab.agent.icon) }
                .tag(Tab.agent)
            NavigationStack { NAIceMoreView() }
                .tabItem { Label(Tab.more.title, systemImage: Tab.more.icon) }
                .tag(Tab.more)
        }
        .tint(Color.naiceGreen)
    }
}

// MARK: - Home View

struct NAIceHomeView: View {
    @State private var showMoodEntry = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                greetingCard; jetztCard; moodCard; dayCard
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMoodEntry) { moodEntrySheet }
    }
    
    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hallo Johannes").font(.title2.weight(.bold)).foregroundColor(.naiceDark)
                Spacer()
                Image(systemName: "house").font(.title3).foregroundColor(.naiceSage)
            }
            Text("Ich bin da, wenn du mich brauchst")
                .font(.subheadline).foregroundColor(.naiceMuted).fixedSize(horizontal: false, vertical: true)
        }.warmCard()
    }
    
    private var jetztCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jetzt").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            HStack(spacing: 10) {
                Circle().fill(Color.naiceGreen).frame(width: 8, height: 8)
                Text("Worauf es heute ankommt").font(.subheadline).foregroundColor(.naiceMuted)
            }
            Text("Keine aktiven Chats").font(.caption).foregroundColor(.naiceSage)
        }.warmCard()
    }
    
    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wie geht es dir?").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            Text("Nimm dir einen Moment und reflektiere dein Befinden.")
                .font(.subheadline).foregroundColor(.naiceMuted)
            Button { showMoodEntry = true } label: {
                Label("Jetzt eintragen", systemImage: "hand.raised.smile")
            }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.naiceGreen, in: RoundedRectangle(cornerRadius: 14))
        }.warmCard()
    }
    
    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dein Tag").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.title3).foregroundColor(.naiceSage)
                Text("Keine Termine \u{2014} Zeit fur deine Projekte")
                    .font(.subheadline).foregroundColor(.naiceMuted).fixedSize(horizontal: false, vertical: true)
            }
        }.warmCard()
    }
    
    private var moodEntrySheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Wie fuhlst du dich?").font(.title2.weight(.bold)).foregroundColor(.naiceDark)
                HStack(spacing: 14) {
                    moodEmoji("\u{1F60A}", label: "Gut")
                    moodEmoji("\u{1F610}", label: "Neutral")
                    moodEmoji("\u{1F614}", label: "Nicht gut")
                }
                Button("Eintragen") { showMoodEntry = false }
                    .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.naiceGreen, in: RoundedRectangle(cornerRadius: 14))
                Spacer()
            }
            .padding(24).warmBackground()
            .navigationTitle("Mood").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Schliessen") { showMoodEntry = false }.foregroundColor(.naiceMuted)
            }}
        }
    }
    
    private func moodEmoji(_ e: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(e).font(.system(size: 36))
            Text(label).font(.caption).foregroundColor(.naiceMuted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.naiceWarmPaper))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.naiceWarmSand.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Life View

struct NAIceLifeView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                meinLebenCard; whoopCard; gewohnheitenCard; finanzenCard; menschenCard
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Leben").navigationBarTitleDisplayMode(.inline)
    }
    
    private var meinLebenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "heart").font(.title2).foregroundColor(.naiceGreen)
                Text("Mein Leben").font(.title2.weight(.bold)).foregroundColor(.naiceDark)
            }
            Text("Deine personliche Ubersicht").font(.subheadline).foregroundColor(.naiceMuted)
        }.warmCard()
    }
    
    private var whoopCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Whoop").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            Text("Verbinde dein Whoop-Konto, um Erholungs-Score, Schlaf, HRV und Belastung direkt in der App zu sehen.")
                .font(.subheadline).foregroundColor(.naiceMuted).fixedSize(horizontal: false, vertical: true)
            Button("Verbinden") {}
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.naiceGreen, in: RoundedRectangle(cornerRadius: 14))
        }.warmCard()
    }
    
    private var gewohnheitenCard: some View {
        NavigationLink { NAIceHabitsView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Gewohnheiten").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                Text("Heute noch nichts geloggt").font(.subheadline).foregroundColor(.naiceMuted)
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk").font(.title3).foregroundColor(.naiceSage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Heutige Challenge:").font(.caption).foregroundColor(.naiceMuted)
                        Text("Gehe 15 Min Spazieren").font(.subheadline.weight(.medium)).foregroundColor(.naiceDark)
                    }
                    Spacer()
                    Button("Loggen") {}.foregroundColor(.naiceDark).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.naiceWarmSand, in: RoundedRectangle(cornerRadius: 10))
                }
                Text("0 % abgeschlossen heute").font(.caption).foregroundColor(.naiceSage)
            }
        }.buttonStyle(NAIceCardButtonStyle()).warmCard()
    }
    
    private var finanzenCard: some View {
        NavigationLink { NAIceFinanceView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Finanzen").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ausgaben").font(.caption).foregroundColor(.naiceMuted)
                        Text("0 Euro").font(.title3.weight(.bold)).foregroundColor(.naiceGreen)
                    }
                    Divider().frame(height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kategorien").font(.caption).foregroundColor(.naiceMuted)
                        Text("0").font(.title3.weight(.bold)).foregroundColor(.naiceDark)
                    }
                }
            }
        }.buttonStyle(NAIceCardButtonStyle()).warmCard()
    }
    
    private var menschenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menschen").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            Text("Keine anstehenden Geburtstage").font(.subheadline).foregroundColor(.naiceMuted)
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.clock").foregroundColor(.naiceSage)
                Text("Kontakte aktualisieren").font(.subheadline).foregroundColor(.naiceSage)
            }
        }.warmCard()
    }
}

// MARK: - Habits View

struct NAIceHabitsView: View {
    private let weekdays: [(String, String)] = [("Mo","14"),("Di","15"),("Mi","16"),("Do","17"),("Fr","18"),("Sa","19"),("So","20")]
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                statusCard; challengeCard; weekReviewSection; weeklyProgressSection
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Gewohnheiten").navigationBarTitleDisplayMode(.large)
    }
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle").font(.title3).foregroundColor(.naiceSage)
                Text("Heute noch nichts geloggt").font(.subheadline).foregroundColor(.naiceMuted)
            }
            Text("Beginne mit deiner heutigen Challenge oder logge eine erledigte Aufgabe.")
                .font(.caption).foregroundColor(.naiceSage).fixedSize(horizontal: false, vertical: true)
        }.warmCard()
    }
    
    private var challengeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.walk").font(.title2).foregroundColor(.naiceGreen)
                Text("Heutige Challenge").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            }
            Text("Gehe 15 Min Spazieren").font(.body.weight(.medium)).foregroundColor(.naiceDark)
            Text("Eine kleine Auszeit an der frischen Luft tut gut und klart den Kopf.")
                .font(.subheadline).foregroundColor(.naiceMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Loggen") {}
                    .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.naiceGreen, in: RoundedRectangle(cornerRadius: 14))
                Button("Uberspringen") {}
                    .foregroundColor(.naiceDark).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.naiceWarmSand, in: RoundedRectangle(cornerRadius: 14))
            }
        }.warmCard()
    }
    
    private var weekReviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ruckblick auf die Woche").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            VStack(spacing: 0) {
                ForEach(weekdays, id: \.1) { entry in
                    HStack(spacing: 12) {
                        Text(entry.0).font(.subheadline.weight(.medium)).foregroundColor(.naiceMuted).frame(width: 28, alignment: .leading)
                        Text(entry.1).font(.subheadline).foregroundColor(.naiceSage).frame(width: 24)
                        RoundedRectangle(cornerRadius: 4).fill(Color.naiceWarmSand.opacity(0.4)).frame(height: 18)
                        Image(systemName: "circle").font(.caption2).foregroundColor(.naiceWarmSand)
                    }.padding(.vertical, 6)
                    if entry.1 != weekdays.last?.1 { Divider().foregroundColor(.naiceWarmSand.opacity(0.3)) }
                }
            }.padding(.horizontal, 4)
        }.warmCard()
    }
    
    private var weeklyProgressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wochenfortschritt").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
            VStack(spacing: 8) {
                ProgressView(value: 0, total: 1).tint(.naiceGreen)
                Text("0 % abgeschlossen").font(.caption).foregroundColor(.naiceMuted)
            }
        }.warmCard()
    }
}

// MARK: - Finance View

struct NAIceFinanceView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Finanzen").font(.title2.weight(.bold)).foregroundColor(.naiceDark)
                    Text("Tippen fur Budget & Analyse").font(.subheadline).foregroundColor(.naiceMuted)
                }.padding(.horizontal, 4)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ausgaben").font(.caption).foregroundColor(.naiceMuted)
                        Text("0 Euro").font(.system(size: 28, weight: .bold)).foregroundColor(.naiceGreen)
                        Text("diesen Monat").font(.caption2).foregroundColor(.naiceSage)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding().warmCard()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kategorien").font(.caption).foregroundColor(.naiceMuted)
                        Text("0").font(.system(size: 28, weight: .bold)).foregroundColor(.naiceDark)
                        Text("aktiv").font(.caption2).foregroundColor(.naiceSage)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding().warmCard()
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Budget Analyse").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                    Text("Verbinde deine Finanzdaten, um Ausgaben und Budgets zu verfolgen.")
                        .font(.subheadline).foregroundColor(.naiceMuted).fixedSize(horizontal: false, vertical: true)
                    Text("Noch keine Daten vorhanden.").font(.caption).foregroundColor(.naiceSage)
                }.padding().warmCard()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tipps").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                    Text("Lege Kategorien fest, um deine Ausgaben zu organisieren. nAIce hilft dir, Muster zu erkennen.")
                        .font(.subheadline).foregroundColor(.naiceMuted).fixedSize(horizontal: false, vertical: true)
                }.padding().warmCard()
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Finanzen").navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - More View

struct NAIceMoreView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                arbeitenSection; wertSection; verbindungenCard; integrationenCard; systemCard; einstellungenCard
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Mehr").navigationBarTitleDisplayMode(.inline)
    }
    
    private var arbeitenSection: some View {
        Group {
            NAiceSectionHeader(icon: "briefcase", title: "Arbeiten")
            moreCard(icon: "note.text", title: "Notizen", subtitle: "0 gespeichert")
            moreCard(icon: "tray", title: "Posteingang", subtitle: "0 ungelesen")
            moreCard(icon: "arrow.triangle.branch", title: "Automatisierung", subtitle: "Wenn X, dann Y")
            moreCard(icon: "list.bullet.clipboard", title: "Agent Regeln", subtitle: nil, badge: ("6 aktiv", Color.naiceGreen))
            moreCard(icon: "server.rack", title: "Server-Workflows", subtitle: "Komplexe Automatisierungen")
        }
    }
    
    private var wertSection: some View {
        Group {
            NAiceSectionHeader(icon: "eurosign", title: "Wert & Transparenz")
            VStack(alignment: .leading, spacing: 10) {
                Text("Was kostet nAIce?").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                VStack(alignment: .leading, spacing: 6) {
                    costRow("iOS Developer Account", "99 Euro / Jahr")
                    costRow("Server", "ca. 6-12 Euro / Monat")
                    costRow("iOS Device", "Einmalig")
                }
            }.padding().warmCard()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield").font(.title3).foregroundColor(.naiceSage)
                    Text("Datenschutz").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                }
                Text("Deine Gesundheitsdaten bleiben auf deinem Gerat. Keine Weitergabe an Dritte.")
                    .font(.subheadline).foregroundColor(.naiceMuted).fixedSize(horizontal: false, vertical: true)
            }.padding().warmCard()
        }
    }
    
    private var verbindungenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title3).foregroundColor(.naiceSage)
                Text("Verbindungen").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.naiceWarmSand)
            }
            Text("Aktive Server-Verbindung").font(.caption).foregroundColor(.naiceMuted)
        }.padding().warmCard()
    }
    
    private var integrationenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.topleft.filled").font(.title3).foregroundColor(.naiceSage)
                Text("Integrationen").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.naiceWarmSand)
            }
            Text("Vernetzt mit deiner digitalen Welt").font(.caption).foregroundColor(.naiceMuted)
        }.padding().warmCard()
    }
    
    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape.2").font(.title3).foregroundColor(.naiceSage)
                Text("System").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.naiceWarmSand)
            }
            Text("App-Version, Speicher, Cache").font(.caption).foregroundColor(.naiceMuted)
        }.padding().warmCard()
    }
    
    private var einstellungenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wrench.adjustable").font(.title3).foregroundColor(.naiceSage)
                Text("Einstellungen").font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.naiceWarmSand)
            }
            Text("Sprache, Design, Benachrichtigungen").font(.caption).foregroundColor(.naiceMuted)
        }.padding().warmCard()
    }
    
    private func moreCard(icon: String, title: String, subtitle: String?, badge: (String, Color)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.title3).foregroundColor(.naiceSage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline.weight(.semibold)).foregroundColor(.naiceDark)
                    if let sub = subtitle { Text(sub).font(.caption).foregroundColor(.naiceMuted) }
                }
                Spacer()
                if let b = badge { NAiceBadge(text: b.0, color: b.1) }
                else { Image(systemName: "chevron.right").font(.caption).foregroundColor(.naiceWarmSand) }
            }
        }.padding().warmCard()
    }
    
    private func costRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.naiceMuted)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundColor(.naiceDark)
        }
    }
}

#Preview {
    ContentView(authManager: AuthManager())
}