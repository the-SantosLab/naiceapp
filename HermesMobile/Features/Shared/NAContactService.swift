import Foundation
import Contacts
import UIKit

// MARK: - Contact CRM Models
struct NAContact: Codable, Identifiable, Equatable {
    let id: String
    var givenName: String
    var familyName: String
    var phoneNumbers: [String]
    var emailAddresses: [String]
    var category: String? // "arbeit", "familie", "freunde", "sonstiges"
    var lastContacted: String? // ISO date
    var notes: String?
    var birthday: String? // MM-dd
    var organization: String?
    var thumbnailPath: String?

    var fullName: String {
        "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
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
            thumbnailPath: nil
        )
    }

    static func == (lhs: NAContact, rhs: NAContact) -> Bool {
        lhs.id == rhs.id
    }
}

struct NAContactInteraction: Codable, Identifiable {
    let id: String
    let contactId: String
    let type: String // "message", "call", "meeting", "note"
    let date: String
    let note: String?
}

// MARK: - Contact CRM Service
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

    func fetchContacts() async {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            lastError = "Keine Kontaktberechtigung"
            return
        }

        isLoading = true
        lastError = nil

        do {
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var result: [NAContact] = []
            try contactStore.enumerateContacts(with: request) { contact, _ in
                // Only include contacts with at least one phone number or email
                if !contact.phoneNumbers.isEmpty || !contact.emailAddresses.isEmpty {
                    result.append(NAContact.fromCNContact(contact))
                }
            }
            self.contacts = result.sorted { $0.familyName < $1.familyName }
            self.isLoading = false
            print("[Contacts] ✅ \(result.count) contacts loaded")
        } catch {
            self.lastError = error.localizedDescription
            self.isLoading = false
            print("[Contacts] ❌ \(error)")
        }
    }

    // Categorize contacts
    func categorizedContacts() -> [(String, [NAContact])] {
        var dict: [String: [NAContact]] = ["arbeit": [], "familie": [], "freunde": [], "sonstiges": []]

        for c in contacts {
            let cat = c.category ?? guessCategory(c)
            dict[cat, default: []].append(c)
        }

        return dict.filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
    }

    private func guessCategory(_ c: NAContact) -> String {
        let org = (c.organization ?? "").lowercased()
        let name = c.fullName.lowercased()

        if org.contains("gmbh") || org.contains("kg") || org.contains("ag") || org.contains("foodloop") || org.contains("naice") || org.contains("santos") {
            return "arbeit"
        }
        if name.contains("jochen") || name.contains("martin") || name.contains("ralf") {
            return "arbeit"
        }

        let surnames = ["schaffer", "müller", "meier", "schmidt", "fischer", "weber", "wagner"]
        for s in surnames {
            if c.familyName.lowercased() == s {
                return "familie"
            }
        }

        return "sonstiges"
    }

    // WhatsApp deep link
    func openWhatsApp(phone: String) {
        let clean = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "https://wa.me/\(clean)") else { return }
        UIApplication.shared.open(url)
    }

    // iMessage deep link
    func openMessage(phone: String) {
        let clean = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "sms:\(clean)") else { return }
        UIApplication.shared.open(url)
    }

    // Call
    func call(phone: String) {
        let clean = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "tel:\(clean)") else { return }
        UIApplication.shared.open(url)
    }
}