import Foundation
import Contacts
import UIKit

// MARK: - Social CRM Models
struct NAContact: Codable, Identifiable, Equatable {
    let id: String
    var givenName: String
    var familyName: String
    var phoneNumbers: [String]
    var emailAddresses: [String]
    var category: String? // "familie", "freunde", "sonstiges"
    var lastContacted: String?
    var notes: String?
    var birthday: String?
    var organization: String?
    var reminderDays: Int

    var fullName: String {
        "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
    }

    var initials: String {
        let parts = [givenName.prefix(1), familyName.prefix(1)]
        return parts.filter { !$0.isEmpty }.map(String.init).joined()
    }

    var daysSinceContacted: Int? {
        guard let lc = lastContacted else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let date = f.date(from: lc) else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }

    var isReachoutDue: Bool {
        guard let days = daysSinceContacted else { return true }
        return days >= reminderDays
    }

    var upcomingBirthday: (daysUntil: Int, dateString: String)? {
        guard let bd = birthday else { return nil }
        let parts = bd.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }
        let cal = Calendar.current
        let now = Date()
        var comps = DateComponents(month: month, day: day)
        comps.year = cal.component(.year, from: now)
        if let bdThisYear = cal.date(from: comps), bdThisYear >= now {
            let daysUntil = cal.dateComponents([.day], from: now, to: bdThisYear).day ?? 0
            let fmt = DateFormatter()
            fmt.dateFormat = "dd.MM."
            return (daysUntil, fmt.string(from: bdThisYear))
        }
        comps.year = cal.component(.year, from: now) + 1
        if let nextBD = cal.date(from: comps) {
            let daysUntil = cal.dateComponents([.day], from: now, to: nextBD).day ?? 0
            let fmt = DateFormatter()
            fmt.dateFormat = "dd.MM."
            return (daysUntil, fmt.string(from: nextBD))
        }
        return nil
    }

    static func fromCNContact(_ c: CNContact) -> NAContact {
        NAContact(
            id: c.identifier,
            givenName: c.givenName,
            familyName: c.familyName,
            phoneNumbers: c.phoneNumbers.map { $0.value.stringValue },
            emailAddresses: c.emailAddresses.map { $0.value as String },
            category: nil,
            lastContacted: nil,
            notes: nil,
            birthday: c.birthday != nil ? String(format: "%02d-%02d", c.birthday!.month ?? 0, c.birthday!.day ?? 0) : nil,
            organization: c.organizationName.isEmpty ? nil : c.organizationName,
            reminderDays: 14
        )
    }

    static func == (lhs: NAContact, rhs: NAContact) -> Bool {
        lhs.id == rhs.id
    }
}

struct NAContactInteraction: Codable, Identifiable {
    let id: String
    let contactId: String
    let type: String
    let date: String
    let note: String?
    let method: String?
}

// MARK: - Social CRM Service
@MainActor
class NAContactService: ObservableObject {
    static let shared = NAContactService()

    private let contactStore = CNContactStore()
    private let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey, CNContactFamilyNameKey,
        CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        CNContactBirthdayKey, CNContactOrganizationNameKey
    ] as! [CNKeyDescriptor]

    @Published var contacts: [NAContact] = []
    @Published var interactions: [NAContactInteraction] = []
    @Published var isLoading = false
    @Published var lastError: String? = nil

    private let prefix = "naice_contact_"

    // MARK: - Local Storage
    private func loadNote(_ id: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + "note_" + id)
    }
    private func saveNote(_ id: String, _ text: String?) {
        UserDefaults.standard.set(text, forKey: prefix + "note_" + id)
    }
    private func loadCategory(_ id: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + "cat_" + id)
    }
    private func saveCategory(_ id: String, _ cat: String?) {
        UserDefaults.standard.set(cat, forKey: prefix + "cat_" + id)
    }
    private func loadLastContacted(_ id: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + "lc_" + id)
    }
    private func saveLastContacted(_ id: String, _ date: String?) {
        UserDefaults.standard.set(date, forKey: prefix + "lc_" + id)
    }
    private func loadReminderDays(_ id: String) -> Int {
        UserDefaults.standard.object(forKey: prefix + "rem_" + id) as? Int ?? 14
    }
    private func saveReminderDays(_ id: String, _ days: Int) {
        UserDefaults.standard.set(days, forKey: prefix + "rem_" + id)
    }

    private func loadInteractions() -> [NAContactInteraction] {
        guard let data = UserDefaults.standard.data(forKey: prefix + "interactions"),
              let decoded = try? JSONDecoder().decode([NAContactInteraction].self, from: data) else { return [] }
        return decoded
    }
    private func saveInteractions(_ items: [NAContactInteraction]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: prefix + "interactions")
    }

    // MARK: - Fetch
    func fetchContacts() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized || status == .limited else {
            lastError = "Keine Kontaktberechtigung"
            return
        }
        isLoading = true
        lastError = nil
        interactions = loadInteractions()

        do {
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var result: [NAContact] = []
            try contactStore.enumerateContacts(with: request) { contact, _ in
                if !contact.phoneNumbers.isEmpty || !contact.emailAddresses.isEmpty || contact.birthday != nil {
                    var c = NAContact.fromCNContact(contact)
                    c.notes = self.loadNote(c.id)
                    c.category = self.loadCategory(c.id)
                    c.lastContacted = self.loadLastContacted(c.id)
                    c.reminderDays = self.loadReminderDays(c.id)
                    result.append(c)
                }
            }
            self.contacts = result.sorted { $0.familyName < $1.familyName }
            self.isLoading = false
        } catch {
            self.lastError = error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: - Social Actions
    func setCategory(_ id: String, _ cat: String) {
        saveCategory(id, cat)
        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            var c = contacts[idx]
            c.category = cat
            contacts[idx] = c
        }
    }

    func setNotes(_ id: String, _ text: String) {
        saveNote(id, text)
        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            var c = contacts[idx]
            c.notes = text
            contacts[idx] = c
        }
    }

    func setReminderDays(_ id: String, _ days: Int) {
        saveReminderDays(id, days)
        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            var c = contacts[idx]
            c.reminderDays = days
            contacts[idx] = c
        }
    }

    func logInteraction(contactId: String, type: String, method: String? = nil, note: String? = nil) {
        let now = ISO8601DateFormatter().string(from: Date())
        let item = NAContactInteraction(id: UUID().uuidString, contactId: contactId, type: type, date: now, note: note, method: method)
        interactions.insert(item, at: 0)
        saveInteractions(Array(interactions.prefix(500)))

        saveLastContacted(contactId, now)
        if let idx = contacts.firstIndex(where: { $0.id == contactId }) {
            var c = contacts[idx]
            c.lastContacted = now
            contacts[idx] = c
        }
    }

    func logCall(_ id: String) { logInteraction(contactId: id, type: "call", method: "phone") }
    func logWhatsApp(_ id: String) { logInteraction(contactId: id, type: "message", method: "whatsapp", note: "WhatsApp") }
    func logMessage(_ id: String) { logInteraction(contactId: id, type: "message", method: "imessage") }
    func logMeeting(_ id: String, _ note: String? = nil) { logInteraction(contactId: id, type: "meeting", method: "inperson", note: note) }

    // MARK: - Insights
    var upcomingBirthdays: [(NAContact, Int, String)] {
        contacts.compactMap { c in
            guard let bd = c.upcomingBirthday else { return nil }
            return (c, bd.daysUntil, bd.dateString)
        }.filter { $0.1 <= 30 }.sorted { $0.1 < $1.1 }
    }

    var reachoutDue: [NAContact] {
        contacts.filter { $0.isReachoutDue }
            .sorted { ($0.daysSinceContacted ?? 99) > ($1.daysSinceContacted ?? 99) }
    }

    func interactionsForContact(_ id: String) -> [NAContactInteraction] {
        interactions.filter { $0.contactId == id }.sorted { $0.date > $1.date }
    }

    func socialCategories() -> [(String, [NAContact], String)] {
        let defs: [(String, String)] = [("familie", "Familie"), ("freunde", "Freunde"), ("sonstiges", "Sonstiges")]
        return defs.compactMap { (key, label) in
            let items = contacts.filter { ($0.category ?? self.guessCategory($0)) == key }
            return items.isEmpty ? nil : (key, items, label)
        }
    }

    private func guessCategory(_ c: NAContact) -> String {
        let surnames = ["schaffer","müller","meier","schmidt","fischer","weber","wagner","huber","bauer","hofmann"]
        if surnames.contains(c.familyName.lowercased()) { return "familie" }
        return "sonstiges"
    }

    // MARK: - Deep Links
    func openWhatsApp(phone: String) {
        let clean = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "https://wa.me/\(clean)") else { return }
        UIApplication.shared.open(url)
    }
    func openMessage(phone: String) {
        let clean = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "sms:\(clean)") else { return }
        UIApplication.shared.open(url)
    }
    func call(phone: String) {
        let clean = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "tel:\(clean)") else { return }
        UIApplication.shared.open(url)
    }
}