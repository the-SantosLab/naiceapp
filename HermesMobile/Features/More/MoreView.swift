import SwiftUI

struct NAIceMoreView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                NAIceSectionLabel(icon: "briefcase", title: "Arbeiten")
                moreR("note.text", "Notizen", "0 gespeichert")
                moreR("tray", "Posteingang", "0 ungelesen")
                moreR("arrow.triangle.branch", "Automatisierung", "Wenn X, dann Y")
                moreR("bolt.fill", "Agent Regeln", "6 aktiv – reagiert auf Daten")
                moreR("server.rack", "Server-Workflows", "Komplexe Automatisierungen")

                NAIceSectionLabel(icon: "eurosign", title: "Wert & Transparenz")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Was kostet nAIce?").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                    Text("iOS-Gerat + Developer Account ($99/J.) + Server (ab $5/Monat). KI via OpenRouter.").font(.subheadline).foregroundColor(.ncMuted)
                }.warmCard()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zeitersparnis pro Tag").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Text("ca. 30 Min – Kein manuelles Planen.")
                    }
                    Spacer()
                    Image(systemName: "clock").font(.title2).foregroundColor(.ncSage)
                }.font(.subheadline).foregroundColor(.ncMuted).warmCard()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Datenschutz").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Text("Gesundheitsdaten bleiben auf dem Gerat. Keine Werbung.")
                    }
                    Spacer()
                    Image(systemName: "lock.shield").font(.title2).foregroundColor(.ncSage)
                }.font(.subheadline).foregroundColor(.ncMuted).warmCard()

                moreS("Verbindungen")
                moreS("Integrationen")
                moreS("System")

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Einstellungen").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                        Text("Server, Profil, App")
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                }.warmCard()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .warmBackground()
        .navigationTitle("Mehr")
        .navigationBarTitleDisplayMode(.inline)
    }

    func moreR(_ i: String, _ t: String, _ s: String) -> some View {
        HStack {
            Image(systemName: i).font(.title3).foregroundColor(.ncSage).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
                Text(s).font(.caption).foregroundColor(.ncMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
        }.warmCard()
    }

    func moreS(_ t: String) -> some View {
        HStack {
            Text(t).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
        }.warmCard()
    }
}