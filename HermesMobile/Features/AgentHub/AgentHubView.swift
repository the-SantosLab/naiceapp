import SwiftUI
import SwiftData

struct AgentHubView: View {
    @Query(sort: \MoodEntry.date, order: .reverse) var moods: [MoodEntry]
    @Query(sort: \HabitLog.date, order: .reverse) var habits: [HabitLog]
    @Query(sort: \Expense.date, order: .reverse) var expenses: [Expense]
    @Environment(\.modelContext) var mc
    @State private var showIdea = false
    @State private var newIdea = ""
    @Binding var requestedNewChat: NewChatRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Greeting
                greetingCard

                // Chat mit Amelia
                Button {
                    let context = NAContextBuilder.buildContext(
                        moods: moods, habits: habits, expenses: expenses,
                        health: HealthManager.shared,
                        calendar: CalendarManager.shared,
                        whoop: NAiceAPI.shared.whoop
                    )
                    requestedNewChat = NewChatRequest(
                        profileName: "santos-copilot",
                        initialDraft: context
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "message.fill").font(.title3).foregroundColor(.white)
                            .frame(width: 36, height: 36).background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mit Amelia chatten").font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                            Text("App-Kontext wird mitgesendet").font(.caption).foregroundColor(.ncMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                    }
                }.warmCard()

                // WHOOP Dashboard
                if let w = NAiceAPI.shared.whoop, w.connected {
                    NAIceSectionLabel(icon: "heart.circle.fill", title: "Gesundheit")
                    VStack(alignment: .leading, spacing: 14) {
                        RecoveryCard(whoop: w)
                        Divider().foregroundColor(.ncSand.opacity(0.3))
                        SleepBreakdownCard(whoop: w)
                    }.warmCard()
                } else if NAiceAPI.shared.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("WHOOP wird geladen...").font(.subheadline).foregroundColor(.ncMuted)
                    }.warmCard()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.slash").font(.title2).foregroundColor(.ncSand)
                        Text("Keine WHOOP-Daten verfugbar").font(.subheadline).foregroundColor(.ncMuted)
                    }.warmCard()
                }

                // Workouts
                if let w = NAiceAPI.shared.whoop, !w.workouts.isEmpty {
                    NAIceSectionLabel(icon: "figure.run", title: "Workouts")
                    WorkoutScrollRow(workouts: w.workouts, whoop: w)
                        .warmCard().padding(0)
                }

                // HealthKit
                if HealthManager.shared.isAuthorized {
                    NAIceSectionLabel(icon: "heart.fill", title: "HealthKit")
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            mini("figure.walk", "\(HealthManager.shared.steps)", "Schritte")
                            mini("heart.fill", "\(Int(HealthManager.shared.heartRate))", "Puls")
                            mini("waveform.path.ecg", "\(Int(HealthManager.shared.hrv))ms", "HRV")
                            mini("moon.fill", String(format: "%.1fh", HealthManager.shared.sleepHours), "Schlaf")
                        }
                    }.warmCard()
                }

                // Ideas
                IdeasCard(
                    showIdea: $showIdea,
                    newIdea: $newIdea,
                    ideas: NAiceAPI.shared.ideas,
                    onSave: {
                        guard !newIdea.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let t = newIdea; newIdea = ""; showIdea = false
                        await NAiceAPI.shared.saveIdea(t)
                    }
                )

                // Tag
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dein Tag").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Text(CalendarManager.shared.todayEvents.isEmpty
                             ? "Keine Termine – Zeit fur deine Projekte"
                             : "\(CalendarManager.shared.todayEvents.count) Termine heute")
                            .font(.subheadline).foregroundColor(.ncMuted)
                    }
                    Spacer()
                    Image(systemName: CalendarManager.shared.todayEvents.isEmpty ? "sun.max.fill" : "calendar.badge.checkmark")
                        .foregroundColor(CalendarManager.shared.todayEvents.isEmpty ? .ncGold : .ncGreen)
                        .font(.title2)
                }.warmCard()

                // Sync Status
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundColor(.ncSage)
                    Text("Sync: \(NASyncService.shared.timeSinceLastSync)").font(.system(size: 10)).foregroundColor(.ncMuted)
                    Spacer()
                }.padding(.horizontal, 4)

                // Lebensbereiche
                NAIceSectionLabel(icon: "square.grid.2x2", title: "Meine Bereiche")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    area("heart.fill", "Gesundheit", .ncRed, AnyView(HealthDetailView(naice: NAiceAPI.shared)))
                    area("briefcase.fill", "Arbeit", .ncGreen, AnyView(WorkDetailView()))
                    area("person.2.fill", "Beziehungen", .ncSage, AnyView(RelationsDetailView()))
                    area("lightbulb.fill", "Kreativitat", .ncGold, AnyView(CreativityDetailView(naice: NAiceAPI.shared)))
                    area("house.fill", "Alltag", .ncDark, AnyView(DailyDetailView()))
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("nAIce")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Circle().fill(Color.ncGreen).frame(width: 48, height: 48)
                    .overlay(Image(systemName: "person.fill").font(.title3).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hallo Johannes").font(.headline.weight(.bold)).foregroundColor(.ncDark)
                    Text(timeGreeting()).font(.subheadline).foregroundColor(.ncMuted)
                }
                Spacer()
            }
        }.warmCard()
    }
}