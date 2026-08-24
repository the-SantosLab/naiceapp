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
    @ObservedObject private var rollup = NARollupService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Greeting with refresh button
                greetingCard

                // Letzter Sync
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundColor(.ncSage)
                    Text("Rollup: \(rollup.rollup?.ts.prefix(16) ?? (NAiceAPI.shared.whoop != nil ? "WHOOP aktiv" : "–"))").font(.system(size: 10)).foregroundColor(.ncMuted)
                    Spacer()
                    if rollup.isLoading {
                        ProgressView().scaleEffect(0.6)
                    }
                }.padding(.horizontal, 4)

                if let err = rollup.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundColor(.ncRed)
                        Text(err).font(.system(size: 10)).foregroundColor(.ncRed)
                        Spacer()
                    }.padding(.horizontal, 4)
                }

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

                // Summary Flags (Amelia's Warnungen)
                if !rollup.flags.isEmpty {
                    ForEach(rollup.flags) { flag in
                        HStack(spacing: 10) {
                            Image(systemName: flag.level == "red" ? "exclamationmark.triangle.fill" : flag.level == "yellow" ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(flag.level == "red" ? .ncRed : flag.level == "yellow" ? .ncGold : .ncGreen)
                                .font(.title3)
                            Text(flag.text).font(.subheadline).foregroundColor(.ncDark)
                            Spacer()
                        }
                        .warmCard()
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                            flag.level == "red" ? Color.ncRed.opacity(0.3) : flag.level == "yellow" ? Color.ncGold.opacity(0.3) : Color.ncGreen.opacity(0.3)
                        ))
                    }
                }

                // WHOOP Dashboard – Rollup (neu) or altes System (Fallback)
                if let w = rollup.whoop {
                    NAIceSectionLabel(icon: "heart.circle.fill", title: "Gesundheit (Amelia)")
                    VStack(alignment: .leading, spacing: 14) {
                        recoveryRow(w)
                        Divider().foregroundColor(.ncSand.opacity(0.3))
                        sleepRow(w)
                    }.warmCard()
                } else if let w = NAiceAPI.shared.whoop, w.connected {
                    NAIceSectionLabel(icon: "heart.circle.fill", title: "Gesundheit")
                    VStack(alignment: .leading, spacing: 14) {
                        RecoveryCard(whoop: w)
                        Divider().foregroundColor(.ncSand.opacity(0.3))
                        SleepBreakdownCard(whoop: w)
                    }.warmCard()
                } else if rollup.isLoading || NAiceAPI.shared.isLoading {
                    VStack(spacing: 12) { ProgressView(); Text("Lade Gesundheitsdaten...").font(.subheadline).foregroundColor(.ncMuted) }.warmCard()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.slash").font(.title2).foregroundColor(.ncSand)
                        Text("Keine WHOOP-Daten verfugbar").font(.subheadline).foregroundColor(.ncMuted)
                    }.warmCard()
                }

                // Workouts – Rollup or Fallback
                let woData = rollup.whoop?.workouts ?? NAiceAPI.shared.whoop?.workouts.map { aw in
                    NAWhoopWorkout(sport: aw.sport, strain: aw.strain, max_hr: aw.maxHr, avg_hr: aw.avgHr, kj: aw.kilojoule, kcal: nil, start: nil, end: nil)
                }
                if let wo = woData, !wo.isEmpty {
                    NAIceSectionLabel(icon: "figure.run", title: "Workouts")
                    workoutRow(Array(wo.prefix(3)))
                }

                // Business
                if let b = rollup.business {
                    NAIceSectionLabel(icon: "briefcase.fill", title: "Business")
                    if let f = b.foodloop {
                        bizCard("foodloop", f.total, f.hot ?? 0, f.statuses ?? [:])
                    }
                    if let n = b.naice {
                        bizCard("nAIce", n.total, n.hot ?? 0, n.statuses ?? [:])
                    }
                }

                // Deals
                if let d = rollup.deals, d.active_deals > 0 {
                    NAIceSectionLabel(icon: "eurosign", title: "Deals")
                    HStack {
                        Text("\(d.active_deals) aktive Deals").font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                        Spacer()
                        Text("\(d.total_value_eur) €").font(.title3.weight(.bold)).foregroundColor(.ncGreen)
                    }.warmCard()
                    ForEach(d.deals?.prefix(3) ?? []) { deal in
                        HStack(spacing: 12) {
                            Circle().fill(Color.ncGreen).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(deal.name).font(.subheadline.weight(.medium)).foregroundColor(.ncDark)
                                Text(deal.status ?? "").font(.caption).foregroundColor(.ncMuted)
                            }
                            Spacer()
                            Text("\(deal.value) €").font(.subheadline.weight(.bold)).foregroundColor(.ncGreen)
                        }.warmCard()
                    }
                }

                // Tasks
                if let t = rollup.tasks, t.active > 0 {
                    NAIceSectionLabel(icon: "checklist", title: "Aufgaben")
                    ForEach(t.tasks?.prefix(3) ?? []) { task in
                        HStack(spacing: 12) {
                            Image(systemName: task.priority == "high" ? "exclamationmark.circle.fill" : "circle")
                                .foregroundColor(task.priority == "high" ? .ncRed : .ncSage)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title).font(.subheadline).foregroundColor(.ncDark).lineLimit(2)
                                if let d = task.deadline { Text("Frist: \(d)").font(.caption).foregroundColor(.ncMuted) }
                            }
                            Spacer()
                        }.warmCard()
                    }
                }

                // Calendar
                if let c = rollup.calendar, c.count > 0 {
                    NAIceSectionLabel(icon: "calendar", title: "Termine")
                    ForEach(c.events?.prefix(3) ?? []) { event in
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.circle").font(.title3).foregroundColor(.ncSage)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).font(.subheadline).foregroundColor(.ncDark)
                                if let s = event.start { Text(s).font(.caption).foregroundColor(.ncMuted) }
                            }
                            Spacer()
                        }.warmCard()
                    }
                }

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
        .refreshable { await refreshAll() }
    }

    private func refreshAll() async {
        await NAiceAPI.shared.fetchWhoop()
        await NAiceAPI.shared.fetchIdeas()
        await rollup.fetch()
        await NAJournalService.shared.fetch()
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
                Button { Task { await refreshAll() } } label: {
                    Image(systemName: "arrow.clockwise").font(.title3).foregroundColor(.ncSage)
                }
                .disabled(rollup.isLoading || NAiceAPI.shared.isLoading)
            }
        }.warmCard()
    }

    private func recoveryRow(_ w: NAWhoopRollup) -> some View {
        Group {
            if let r = w.recovery {
                HStack {
                    Text("Recovery").font(.subheadline).foregroundColor(.ncMuted)
                    Spacer()
                    Text("\(r.score)%").font(.title2.weight(.bold)).foregroundColor(r.score > 60 ? .ncGreen : .ncRed)
                }
                ProgressView(value: Double(r.score) / 100).tint(r.score > 60 ? .ncGreen : .ncRed)
                HStack(spacing: 0) {
                    mini("heart.fill", "\(r.rhr)", "Puls")
                    mini("waveform.path.ecg", "\(r.hrv)ms", "HRV")
                    if let s = r.spo2 { mini("drop.fill", "\(Int(s))%", "SpO2") }
                }
            }
        }
    }

    private func sleepRow(_ w: NAWhoopRollup) -> some View {
        Group {
            if let s = w.sleep {
                HStack {
                    Text("Schlaf").font(.subheadline).foregroundColor(.ncMuted)
                    Spacer()
                    Text(String(format: "%.1fh", s.net_hours)).font(.title3.weight(.bold)).foregroundColor(.ncDark)
                    if let e = s.efficiency_pct { Text("(\(Int(e))%)").font(.caption).foregroundColor(.ncMuted) }
                }
                // Sleep phases bar
                if s.deep_minutes + s.rem_minutes + s.light_minutes + s.awake_minutes > 0 {
                    let total = Double(s.deep_minutes + s.rem_minutes + s.light_minutes + s.awake_minutes)
                    HStack(spacing: 3) {
                        phaseBar(.ncDark, Double(s.deep_minutes) / total, "Deep")
                        phaseBar(.ncGreen, Double(s.rem_minutes) / total, "REM")
                        phaseBar(Color.ncSand.opacity(0.5), Double(s.light_minutes) / total, "Light")
                        phaseBar(.ncRed.opacity(0.3), Double(s.awake_minutes) / total, "Awake")
                    }
                    HStack {
                        leg("Deep", Color.ncDark); leg("REM", Color.ncGreen)
                        leg("Light", Color.ncSand.opacity(0.5)); leg("Awake", Color.ncRed.opacity(0.3))
                    }
                }
                if let w = w.cycle {
                    HStack {
                        Text("Strain: \(String(format: "%.1f", w.strain ?? 0))").font(.caption).foregroundColor(.ncMuted)
                        Spacer()
                        if let avg = w.avg_hr { Text("Puls Ø: \(avg)").font(.caption).foregroundColor(.ncMuted) }
                    }
                }
            }
        }
    }

    private func workoutRow(_ workouts: [NAWhoopWorkout]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(workouts.indices, id: \.self) { i in
                    let wo = workouts[i]
                    VStack(spacing: 6) {
                        Image(systemName: sportIcon(wo.sport)).font(.title2).foregroundColor(.ncGreen)
                        Text(wo.sport.capitalized).font(.caption).foregroundColor(.ncDark)
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundColor(.ncGold)
                            Text(String(format: "%.1f", wo.strain)).font(.caption2.weight(.semibold)).foregroundColor(.ncDark)
                        }
                    }
                    .frame(width: 72, height: 80)
                    .background(Color.ncPaper, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand.opacity(0.4)))
                }
            }.padding(.horizontal, 4)
        }
    }

    private func bizCard(_ name: String, _ total: Int, _ hot: Int, _ statuses: [String: Int]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: name == "foodloop" ? "fork.knife" : "brain.head.profile")
                .font(.title3).foregroundColor(.ncSage).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.capitalized).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                Text("\(total) Kontakte · \(hot) heiss").font(.caption).foregroundColor(.ncMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
        }.warmCard()
    }

    private func phaseBar(_ color: Color, _ pct: Double, _ label: String) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color).frame(height: 12)
            .frame(maxWidth: pct > 0.01 ? .infinity : 0)
    }

    private func leg(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(t).font(.system(size: 9)).foregroundColor(.ncMuted)
        }
    }

    private func sportIcon(_ s: String) -> String {
        switch s.lowercased() {
        case "walking": return "figure.walk"
        case "running": return "figure.run"
        case "cycling": return "bicycle"
        case "swimming": return "figure.pool.swim"
        case "fitness": return "dumbbell.fill"
        case "yoga": return "figure.mind.and.body"
        default: return "figure.mixed.cardio"
        }
    }
}

extension NACalendarEvent: Identifiable {
    var id: String { title }
}