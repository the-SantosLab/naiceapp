import SwiftUI
import SwiftData

struct NAIceLifeView: View {
    @ObservedObject var services: ServiceManager
    @Query(sort: \HabitLog.date, order: .reverse) var habits: [HabitLog]
    @Query(sort: \Expense.date, order: .reverse) var expenses: [Expense]
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
                Text("Dein Leben").font(.title2.weight(.bold)).foregroundColor(.ncDark)
                    .padding(.horizontal, 4).padding(.top, 4)

                // Mein Leben
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill").font(.title2).foregroundColor(.ncGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mein Leben").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Text("Tippen fur Details").font(.subheadline).foregroundColor(.ncMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                }.warmCard()

                // nAIce Insights
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "lightbulb.fill").font(.title2).foregroundColor(.ncGold)
                        Text("nAIce Insights").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                    }
                    Text("Verbinde Dienste fur personalisierte Insights.").font(.subheadline).foregroundColor(.ncMuted)
                    HStack(spacing: 6) {
                        naBadge("heart.fill", "Health", HealthManager.shared.isAuthorized)
                        naBadge("calendar", "Kalender", CalendarManager.shared.isAuthorized)
                        naBadge("person.crop.circle", "Kontakte", services.contactsAuthorized)
                        naBadge("location.fill", "Standort", services.locationAuthorized)
                        naBadge("bell.fill", "Reminders", services.remindersAuthorized)
                    }.padding(.top, 4)
                }.warmCard()

                // Whoop
                VStack(alignment: .leading, spacing: 10) {
                    Text("Whoop").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("Zeigt Recovery Score, HRV, Ruhepuls und Strain.").font(.subheadline).foregroundColor(.ncMuted)
                    HStack {
                        Image(systemName: "heart.circle").font(.title3).foregroundColor(.ncGreen)
                        Text("Whoop verbinden").font(.subheadline.weight(.medium)).foregroundColor(.ncGreen)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncGreen.opacity(0.15)))
                }.warmCard()

                // Gewohnheiten
                NavigationLink(destination: NAIceHabitsView()) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Gewohnheiten").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                        }
                        Text(habits.isEmpty ? "Heute noch nichts geloggt" : "\(habits.filter { Calendar.current.isDateInToday($0.date) }.count) heute geloggt")
                            .font(.subheadline).foregroundColor(.ncMuted)
                        HStack(spacing: 10) {
                            Image(systemName: "figure.walk").font(.title3).foregroundColor(.ncSage)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Heutige Challenge:").font(.caption).foregroundColor(.ncMuted)
                                Text("Gehe 15 Min Spazieren").font(.subheadline.weight(.medium)).foregroundColor(.ncDark)
                            }
                            Spacer()
                            Button("Loggen") { showHabitLog = true }
                                .font(.caption.weight(.semibold)).foregroundColor(.ncGreen)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.ncGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.ncGreen.opacity(0.15)))
                        }
                    }
                }.warmCard().buttonStyle(PlainButtonStyle())

                // Finanzen
                NavigationLink(destination: NAIceFinanceView()) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Finanzen").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                                Text("Tippen fur Budget & Analyse").font(.caption).foregroundColor(.ncMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                        }
                        let monthly = expenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ausgaben").font(.caption).foregroundColor(.ncMuted)
                                Text("\(Int(monthly.reduce(0) { $0 + $1.amount })) Euro")
                                    .font(.title3.weight(.bold)).foregroundColor(.ncGreen)
                            }
                            Divider().frame(height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kategorien").font(.caption).foregroundColor(.ncMuted)
                                Text("\(Set(monthly.map { $0.category }).count)")
                                    .font(.title3.weight(.bold)).foregroundColor(.ncDark)
                            }
                        }
                    }
                }.warmCard().buttonStyle(PlainButtonStyle())

                // Menschen
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Menschen").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                    }
                    Text("Keine Geburtstage in den nachsten 14 Tagen.").font(.subheadline).foregroundColor(.ncMuted)
                    VStack(spacing: 8) {
                        contactRow("Jochen Rupp", "J")
                        Divider().foregroundColor(.ncSand.opacity(0.3))
                        contactRow("Martin Grassl", "M")
                    }
                }.warmCard()

                // Apple Daten
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Apple Daten").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.ncGreen).font(.title3)
                    }
                    Text("Alles aktuell – keine anstehenden Termine oder Aufgaben.").font(.subheadline).foregroundColor(.ncMuted)
                    HStack(spacing: 6) {
                        naBadge("calendar", "Kalender", CalendarManager.shared.isAuthorized)
                        naBadge("bell.fill", "Erinnerungen", services.remindersAuthorized)
                        naBadge("location.fill", "Standort", services.locationAuthorized)
                        naBadge("person.crop.circle", "Kontakte", services.contactsAuthorized)
                        naBadge("note.text", "Notizen", false)
                    }.padding(.top, 4)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
    }

    func naBadge(_ icon: String, _ label: String, _ connected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8))
            Text(label).font(.system(size: 9))
        }
        .foregroundColor(connected ? .ncGreen : .ncSand)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((connected ? Color.ncGreen : Color.ncSand).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke((connected ? Color.ncGreen : Color.ncSand).opacity(0.2), lineWidth: 0.5))
    }

    func contactRow(_ name: String, _ initial: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.ncSage.opacity(0.2)).frame(width: 34, height: 34)
                Text(initial).font(.subheadline.weight(.bold)).foregroundColor(.ncDark)
            }
            Text(name).font(.subheadline).foregroundColor(.ncDark)
            Spacer()
            Button("Kontakt auffrischen?") { }.font(.caption).foregroundColor(.ncGreen)
        }
    }
}