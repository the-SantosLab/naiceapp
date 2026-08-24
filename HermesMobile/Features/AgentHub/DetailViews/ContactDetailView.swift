import SwiftUI

// MARK: - Contact Detail View (Social CRM)
struct ContactDetailView: View {
    let contact: NAContact
    @ObservedObject private var svc = NAContactService.shared
    @State private var notes = ""
    @State private var selectedCategory = "sonstiges"
    @State private var showActionSheet = false
    @State private var showMeetingNote = false
    @State private var meetingNote = ""
    @State private var reminderDays: Double = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.ncGreen.opacity(0.15)).frame(width: 72, height: 72)
                        Text(contact.initials).font(.title.weight(.semibold)).foregroundColor(.ncGreen)
                    }
                    Text(contact.fullName).font(.title2.weight(.bold)).foregroundColor(.ncDark)
                    if let org = contact.organization {
                        Text(org).font(.subheadline).foregroundColor(.ncMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                // Quick Actions
                VStack(spacing: 10) {
                    Text("Aktionen").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    HStack(spacing: 12) {
                        QuickActionButton(icon: "phone.fill", label: "Anrufen", color: .ncGreen) {
                            if let p = contact.phoneNumbers.first {
                                svc.call(phone: p)
                                svc.logCall(contact.id)
                            }
                        }
                        QuickActionButton(icon: "message.fill", label: "WhatsApp", color: .ncGreen) {
                            if let p = contact.phoneNumbers.first {
                                svc.openWhatsApp(phone: p)
                                svc.logWhatsApp(contact.id)
                            }
                        }
                        QuickActionButton(icon: "bubble.left.fill", label: "Nachricht", color: .ncSage) {
                            if let p = contact.phoneNumbers.first {
                                svc.openMessage(phone: p)
                                svc.logMessage(contact.id)
                            }
                        }
                        QuickActionButton(icon: "person.2.fill", label: "Treffen", color: .ncGold) {
                            showMeetingNote = true
                        }
                    }
                }.warmCard()

                // Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Info").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    if let p = contact.phoneNumbers.first {
                        infoRow("Telefon", "tel.fill", p)
                    }
                    if let e = contact.emailAddresses.first {
                        infoRow("E-Mail", "envelope.fill", e)
                    }
                    if let bd = contact.birthday {
                        infoRow("Geburtstag", "star.fill", String(bd.prefix(5)))
                    }
                    if let days = contact.daysSinceContacted {
                        infoRow("Zuletzt", "clock.fill", days == 0 ? "Heute" : "vor \(days) Tagen")
                    } else {
                        infoRow("Zuletzt", "clock.fill", "Noch nie kontaktiert")
                    }
                }.warmCard()

                // Category
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kategorie").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Picker("", selection: $selectedCategory) {
                        Text("Familie").tag("familie")
                        Text("Freunde").tag("freunde")
                        Text("Sonstiges").tag("sonstiges")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedCategory) { _, new in
                        svc.setCategory(contact.id, new)
                    }
                }.warmCard()

                // Reminder Interval
                VStack(alignment: .leading, spacing: 8) {
                    Text("Erinnerung").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    HStack {
                        Text("Alle \(Int(reminderDays)) Tage erinnern")
                            .font(.subheadline).foregroundColor(.ncMuted)
                        Spacer()
                    }
                    Slider(value: $reminderDays, in: 3...30, step: 1) {
                        Text("Intervall")
                    } onEditingChanged: { _ in
                        svc.setReminderDays(contact.id, Int(reminderDays))
                    }
                    .tint(.ncGreen)
                }.warmCard()

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notizen").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    TextEditor(text: $notes)
                        .font(.subheadline)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand))
                    Button("Speichern") {
                        svc.setNotes(contact.id, notes)
                    }
                    .font(.caption.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 9))
                }.warmCard()

                // Interaction History
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verlauf").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    let hist = svc.interactionsForContact(contact.id)
                    if hist.isEmpty {
                        Text("Noch keine Interaktionen aufgezeichnet.")
                            .font(.subheadline).foregroundColor(.ncMuted)
                    } else {
                        ForEach(hist.prefix(20)) { item in
                            HStack(spacing: 10) {
                                Image(systemName: interactionIcon(item.type))
                                    .foregroundColor(interactionColor(item.type))
                                    .font(.caption)
                                Text(interactionLabel(item))
                                    .font(.caption).foregroundColor(.ncDark)
                                Spacer()
                                Text(formatDate(item.date))
                                    .font(.caption2).foregroundColor(.ncMuted)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle(contact.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notes = contact.notes ?? ""
            selectedCategory = contact.category ?? "sonstiges"
            reminderDays = Double(contact.reminderDays)
        }
        .alert("Treffen notieren", isPresented: $showMeetingNote) {
            TextField("Notiz (optional)", text: $meetingNote)
            Button("Loggen") {
                svc.logMeeting(contact.id, meetingNote.isEmpty ? nil : meetingNote)
                meetingNote = ""
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    func infoRow(_ label: String, _ icon: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.caption).foregroundColor(.ncSage).frame(width: 20)
            Text(label).font(.caption).foregroundColor(.ncMuted)
            Spacer()
            Text(value).font(.subheadline).foregroundColor(.ncDark)
        }
    }

    func interactionIcon(_ type: String) -> String {
        switch type {
        case "call": return "phone.fill"
        case "message": return "message.fill"
        case "meeting": return "person.2.fill"
        default: return "note.text"
        }
    }

    func interactionColor(_ type: String) -> Color {
        switch type {
        case "call": return .ncGreen
        case "message": return .ncSage
        case "meeting": return .ncGold
        default: return .ncMuted
        }
    }

    func interactionLabel(_ item: NAContactInteraction) -> String {
        var parts = [item.type.capitalized]
        if let n = item.note, !n.isEmpty { parts.append(n) }
        if let m = item.method { parts.append("via \(m)") }
        return parts.joined(separator: " · ")
    }

    func formatDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let d = f.date(from: iso) else { return String(iso.prefix(10)) }
        let out = DateFormatter()
        out.dateFormat = "dd.MM."
        return out.string(from: d)
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
                    .cornerRadius(12)
                Text(label).font(.caption2).foregroundColor(.ncDark)
            }
            .frame(maxWidth: .infinity)
        }
    }
}