import SwiftUI

// MARK: - Health Detail View
struct HealthDetailView: View {
    @ObservedObject var naice: NAiceAPI
    @ObservedObject var health = HealthManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Gesundheit").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                Text("Deine Vitaldaten auf einen Blick.").font(.subheadline).foregroundColor(.ncMuted)

                if !(naice.whoop?.connected ?? false) {
                    Link(destination: URL(string: "https://health.santoslab.de/auth/whoop")!) {
                        Text("Whoop verbinden").foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                if let w = naice.whoop, w.connected {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Whoop Recovery").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                            Spacer()
                            Text("\(w.recoveryScore)%").font(.largeTitle.weight(.bold))
                                .foregroundColor(w.recoveryScore > 60 ? .ncGreen : .ncRed)
                        }
                        ProgressView(value: Double(w.recoveryScore) / 100)
                            .tint(w.recoveryScore > 60 ? .ncGreen : .ncRed)
                        Divider()
                        hRow("HRV", "\(Int(w.hrv)) ms")
                        hRow("Ruhepuls", "\(w.restingHeartRate) bpm")
                        hRow("Strain", String(format: "%.1f", w.strain))
                        hRow("Schlaf", String(format: "%.1f h", w.sleepHours))
                    }.warmCard()
                }

                if health.isAuthorized {
                    VStack(spacing: 10) {
                        Text("HealthKit").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        hRow("Schritte", "\(health.steps)")
                        hRow("Puls", "\(Int(health.heartRate)) bpm")
                        hRow("HRV", "\(Int(health.hrv)) ms")
                        hRow("Schlaf", String(format: "%.1f h", health.sleepHours))
                    }.warmCard()
                }

                VStack(spacing: 8) {
                    Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Deine HRV und Schlafdaten geben Aufschluss uber deine Erholung. Ein Recovery Score uber 60% bedeutet, dass dein Korper bereit fur Belastung ist.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()

                VStack(spacing: 8) {
                    Text("Whoop API Echtzeitdaten").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Der Whoop-Server liefert deine aktuellen Vitaldaten automatisch. Recovery, HRV, Schlaf und Strain werden mit jeder Aktualisierung synchronisiert.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Gesundheit")
        .navigationBarTitleDisplayMode(.large)
    }

    func hRow(_ t: String, _ v: String) -> some View {
        HStack {
            Text(t).font(.subheadline).foregroundColor(.ncDark)
            Spacer()
            Text(v).font(.subheadline.weight(.bold)).foregroundColor(.ncDark)
        }.padding(.vertical, 2)
    }
}

// MARK: - Work Detail View
struct WorkDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Arbeit").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                Text("Deine Produktivitat im Uberblick.").font(.subheadline).foregroundColor(.ncMuted)
                wCard("Chat Sessions", "Dein Hermes Agent ist bereit. Offne den Agent-Tab fur Sessions und Chats.", "bubble.left.and.bubble.right")
                wCard("Notizen", "Erfasse und organisiere Gedanken. Der Agent fasst zusammen.", "note.text")
                wCard("Proaktive Zusammenfassung", "Dein Agent kann regelmassig Zusammenfassungen deiner Chats und Notizen erstellen und dir Vorschlage unterbreiten.", "text.bubble.fill")
                wCard("Aufgaben & Fokus", "Der Agent merkt sich deine Arbeitszeiten. Er schlagt optimale Fenster fur tiefe Arbeit vor.", "brain.head.profile")
                VStack(spacing: 8) {
                    Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Deine produktivste Zeit ist am Vormittag. Plane wichtige Aufgaben zwischen 9 und 12 Uhr.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Arbeit")
        .navigationBarTitleDisplayMode(.large)
    }

    func wCard(_ t: String, _ txt: String, _ i: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: i).font(.title2).foregroundColor(.ncSage).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                Text(txt).font(.caption).foregroundColor(.ncMuted)
            }
        }.warmCard()
    }
}

// MARK: - Relations Detail View
struct RelationsDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Beziehungen").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                Text("Deine Kontakte und Verbindungen.").font(.subheadline).foregroundColor(.ncMuted)
                rCard("Geburtstage", "Keine Geburtstage in den nachsten 14 Tagen – ruhige Phase.", "star.fill")
                rCard("Jochen Rupp", "Zuletzt aktualisiert vor 3 Monaten. Vorschlag: Kurze Nachricht.", "person.crop.circle")
                rCard("Martin Grassl", "Zuletzt aktualisiert vor 2 Monaten. Vorschlag: Kaffee einladen.", "person.crop.circle")
                rCard("Familie", "Regelmaiger Kontakt starkt Bindungen. Dein Agent erinnert an Geburtstage und Anlasse.", "house.fill")
                VStack(spacing: 8) {
                    Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Einmal pro Woche eine kurze Nachricht an einen Kontakt kann Beziehungen starken. Dein Agent erinnert dich.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Beziehungen")
        .navigationBarTitleDisplayMode(.large)
    }

    func rCard(_ t: String, _ txt: String, _ i: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: i).font(.title2).foregroundColor(.ncSage).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                Text(txt).font(.caption).foregroundColor(.ncMuted)
            }
        }.warmCard()
    }
}

// MARK: - Creativity Detail View
struct CreativityDetailView: View {
    @ObservedObject var naice: NAiceAPI
    @State private var newIdea = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Kreativitat").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                Text("Sammle und entwickle Ideen mit deinem Agent.").font(.subheadline).foregroundColor(.ncMuted)

                HStack(spacing: 8) {
                    TextField("Neue Idee...", text: $newIdea)
                        .padding(10).background(Color.ncPaper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand))
                    Button("Speichern") {
                        let t = newIdea; newIdea = ""
                        Task { await naice.saveIdea(t) }
                    }
                    .font(.caption.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 9))
                }

                if naice.ideas.isEmpty {
                    Text("Noch keine Ideen gespeichert. Leg los!").font(.subheadline).foregroundColor(.ncMuted)
                }
                ForEach(naice.ideas) { idea in
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill").font(.title3).foregroundColor(.ncGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.text).font(.subheadline).foregroundColor(.ncDark)
                            Text(idea.createdAt, style: .date).font(.caption).foregroundColor(.ncMuted)
                        }
                        Spacer()
                    }.warmCard()
                }

                cCard("Brainstorming-Partner", "Dein Agent kann mit dir zusammen Ideen entwickeln, erweitern und strukturieren. Einfach im Chat starten.")
                cCard("Kreativ-Routinen", "Die besten Ideen kommen beim Spazierengehen oder unter der Dusche. Halte sie sofort fest – dein nAIce Agent speichert fur dich.", "brain.head.profile")
                VStack(spacing: 8) {
                    Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Setze dir ein Ziel: 3 Ideen pro Woche. Dein Agent hilft dir, sie zu sortieren und weiterzuentwickeln.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Kreativitat")
        .navigationBarTitleDisplayMode(.large)
    }

    func cCard(_ t: String, _ txt: String, _ i: String = "lightbulb") -> some View {
        HStack(spacing: 12) {
            Image(systemName: i).font(.title2).foregroundColor(.ncGold).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                Text(txt).font(.caption).foregroundColor(.ncMuted)
            }
        }.warmCard()
    }
}

// MARK: - Daily Detail View
struct DailyDetailView: View {
    @ObservedObject var calendar = CalendarManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Alltag").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                Text("Dein Tagesablauf im Griff.").font(.subheadline).foregroundColor(.ncMuted)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(calendar.todayEvents.isEmpty ? "Keine Termine heute" : "\(calendar.todayEvents.count) Termine heute")
                            .font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Text("Standort: Dietmannsried – sonnig, 22°C").font(.subheadline).foregroundColor(.ncMuted)
                    }
                    Spacer()
                    Image(systemName: "sun.max.fill").font(.title2).foregroundColor(.ncGold)
                }.warmCard()

                dCard("Morgendlicher Check-in", "Dein Agent begrusst dich mit Wetter, Terminen und Health-Daten. Jeden Morgen – bevor du fragst.")
                dCard("Standort-basierte Erinnerungen", "Wenn du nach Hause kommst: Erinnerung an Einkaufe. Wenn du das Buro verlassen hast: Chat-Zusammenfassung.")
                dCard("Abendliche Reflexion", "Was war gut heute? Was morgen besser? Der Agent lernt aus deinen Antworten.")
                dCard("Routinen & Gewohnheiten", "Dein Agent erkennt Muster in deinem Tag und schlagt Optimierungen vor.")

                VStack(spacing: 8) {
                    Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Routinen geben Struktur, aber Flexibilitat macht glucklich. Dein nAIce Agent lernt, wann du Struktur brauchst und wann Freiheit.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Alltag")
        .navigationBarTitleDisplayMode(.large)
    }

    func dCard(_ t: String, _ txt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
            Text(txt).font(.caption).foregroundColor(.ncMuted)
        }.warmCard()
    }
}

// MARK: - Workouts Detail View
struct WorkoutsDetailView: View {
    let whoop: NAWhoop

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Workouts").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                Text("Die letzten \(whoop.workouts.count) Aktivitaten").font(.subheadline).foregroundColor(.ncMuted)

                ForEach(whoop.workouts) { wo in
                    HStack(spacing: 14) {
                        Image(systemName: wo.sportIcon).font(.title2).foregroundColor(.ncGreen).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wo.sport.capitalized).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                            Text("\(wo.durationMinutes) min").font(.caption).foregroundColor(.ncMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundColor(.ncGold)
                                Text(String(format: "%.1f", wo.strain)).font(.caption.weight(.semibold)).foregroundColor(.ncDark)
                            }
                            HStack(spacing: 2) {
                                Image(systemName: "heart.fill").font(.system(size: 8)).foregroundColor(.ncRed)
                                Text("\(wo.avgHr) Ø").font(.caption).foregroundColor(.ncMuted)
                            }
                        }
                    }.warmCard()
                }

                VStack(spacing: 8) {
                    Text("AI-Tipp").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Deine Workout-Strain summiert sich auf \(String(format: "%.1f", whoop.workouts.reduce(0) { $0 + $1.strain })). Dein Korper signalisiert mit einem Recovery von \(whoop.recoveryScore)%: Heute kein Strain uber 10.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
    }
}