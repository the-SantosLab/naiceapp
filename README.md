<div align="center">
  <img src="https://agent.santoslab.de/naice-app/icon.png" width="100" alt="nAIce Logo" />
  <h1 align="center">nAIce</h1>
  <p align="center"><strong>Tools fragen. nAIce weiss.</strong></p>
  <p align="center">
    Native iOS App für den nAIce KI-Agenten —<br />
    Dein Leben, Dein Business, Dein Agent. Auf Deinem iPhone.
  </p>

  <p align="center">
    <a href="#features">Features</a> •
    <a href="#build">Build</a> •
    <a href="#architecture">Architektur</a> •
    <a href="#license">License</a>
  </p>

  <p align="center">
    <img src="https://img.shields.io/badge/iOS-18.0+-000?style=flat&logo=apple&labelColor=1A140D" />
    <img src="https://img.shields.io/badge/SwiftUI-Native-3D5A47?style=flat&logo=swift&labelColor=1A140D" />
    <img src="https://img.shields.io/badge/Mac_Catalyst-✔-FBF4E2?style=flat&labelColor=1A140D" />
    <img src="https://img.shields.io/badge/watchOS-✔-3D5A47?style=flat&labelColor=1A140D" />
    <img src="https://img.shields.io/badge/Widget-✔-8A8270?style=flat&labelColor=1A140D" />
    <img src="https://img.shields.io/badge/License-MIT-FBF4E2?style=flat&labelColor=1A140D" />
  </p>
</div>

<br />

---

**nAIce** ist Dein persönlicher KI-Agent auf dem iPhone — kein WebView, kein Wrapper, echte Native SwiftUI. Verbinde Dich mit Deinem eigenen Server und habe Deine gesamte Lebens- und Geschäftswelt in der Tasche.

> 💡 **Philosophie:** Dein Telefon ist die Steuerungsebene, nicht die Rechenebene. Der Agent, seine Tools und Deine Daten bleiben auf Deiner Hardware.

---

## 📱 Features

### 🏠 Home – Dein Command Center
- **Tägliche Briefings** vom Agenten (Morgen/Mittag/Abend)
- **Proaktive Insights** basierend auf WHOOP, Kalender & CRM
- **Schnell-Erfassung** für Stimmung, Gewohnheiten & Ausgaben
- **Business-Rollup** mit allen offenen Deals, Leads & Aufgaben
- **WHOOP** Recovery-Score, HRV, Schlafphasen & Workouts auf einen Blick

### 🌿 Leben – Life Dashboard
- **Amelias Tages-Impression** – KI-generierte Zusammenfassung Deines Tages
- **6-Dimensions-RadarChart** – Gesundheit, Finanzen, Menschen, Produktivität, Wohlbefinden, Fokus
- **Zeitstrahl der nächsten 24h** – Termine, Tasks & Gewohnheiten
- **Wöchentlicher Trend** – Recovery-Verlauf, Journal-Aktivität, Deal-Entwicklung
- **4 Bereichskacheln** – Gesundheit, Finanzen, Menschen, Gewohnheiten mit Drill-Down

### ✅ Aufgaben – Task-Management
- Sync von Server-Tasks (aus console.db)
- Priorisierte Anzeige mit Deadlines & Projekten
- Badge im Tab für offene Aktionspunkte

### 🤖 Agent – Chat mit Amelia
- Vollständiger Chat mit Deinem persönlichen KI-Agenten **Amelia**
- SSE-Streaming für Echtzeit-Antworten
- Thinking- & Tool-Call-Detailansicht
- Model-, Profile- & Workspace-Auswahl
- Sitzungsverlauf & Suche
- Datei- & Bild-Upload
- **Read-only-Badge** für Telegram-importierte Sitzungen

### ⚙️ Mehr – Integrationen & Einstellungen
- **Apple Dienste** – Health, Kalender, Kontakte, Spracherkennung, Verschlüsselte Notizen
- **Biometrische Auth** – Face ID / Touch ID App-Lock
- **KI-Workflows** – Automatisierte Agent-Aktionen
- **Sprach-Befehle** – Freihändige Steuerung
- **WhatsApp-Integration** – Chat-Übersicht mit ungelesenen Nachrichten
- **Push-Benachrichtigungen** – Server-seitige Alarme & Agent-Updates
- **Server-Status** – Verbindung, Agent Memory, Mac Agent
- **OTA-Update** – In-App-Update-Prüfung

### 🍎 Plattform
- **iPhone** (iOS 18+) – Vollständige SwiftUI-App
- **iPad** – Optimiert mit Sidebar-Unterstützung
- **Mac Catalyst** – Läuft nativ auf dem Mac
- **Apple Watch** – nAIce Watch App mit Komplikationen
- **Widgets** – Home Screen Widget + Dynamic Island
- **Live Activities** – Running Agent-Anzeige
- **Deep Links** – `naice://chat`, `naice://journal`, `naice://log/mood`
- **Siri Shortcuts** & **Spotlight Search**

### 🔌 Backend-Integrationen
| System | Daten |
|--------|-------|
| **WHOOP** | Recovery, HRV, Schlaf, Workouts, Strain |
| **nAIce** | 324 Leads, Pitch-Status |
| **foodloop** | 133 Restaurant-Pipeline-Einträge |
| **Schaffer-Wine** | 140 B2B-Leads, Pageviews, Subscribers |
| **Parcelmate** | 229 Leads, Shipments, Newsletter |
| **CRM** | 484 Clients, 603k€ Pipeline, Cold Calls, Alerts |
| **Revenue** | Monatliche Einnahmen, Buchungen, Trends |
| **Knowledge Graph** | Wissensbasis pro Client |
| **Agent Memory** | Persistente Agent-Fakten |

---

## 🏗 Architektur

Die App folgt einer **Server-getriebenen Architektur**, bei der die meiste Logik auf dem eigenen Server läuft und das iPhone als reichhaltiger Client dient.

```
┌────────────────┐  ┌──────────────────────┐
│  iPhone (nAIce)  │  │  Server (santoslab.de)  │
│  SwiftUI       │◄──│  Cockpit API (:8485)   │
│  TabView        │     │  CRM API (:8486)       │
│  Home / Leben   │     │  Push Service (:8487)  │
│  Aufgaben / Agent│     │  WhatsApp Bridge       │
│  Mehr           │     │  WHOOP Sync            │
└────────────────┘  │  Console DB             │
                    └──────────────────────┘
        │
        ├── HealthKit – Lokale Gesundheitsdaten
        ├── EKEventStore – Lokale Kalenderdaten
        ├── CNContactStore – Lokale Kontaktdaten
        └── SwiftData – Mood, Habits, Ausgaben (lokal)
```

### Key Konzepte

- **NARollupService** – Zentrale Daten-Schnittstelle, holt regelmässig den aktuellen Rollup vom Server
- **NARollup** – Kompaktes JSON mit WHOOP, Business, CRM, Kalender, Tasks, Journal, Revenue, Knowledge
- **Amelia as OS** – Überall präsente Kontextleiste & "Frag Amelia"-Button auf jeder Karte
- **Tolerantes Decoding** – Alle neuen Felder sind optional, die App bricht nicht bei API-Änderungen
- **Design System** – Creme #FBF4E2, Dunkelgrün #3D5A47, Dunkelbraun #1A140D, Grau #8A8270

---

## 🚀 Build

### Voraussetzungen

- Xcode 16+
- iOS 18.0+ SDK
- Swift 6+
- Ein SantosLab GitHub-Token (für private Abhängigkeiten)

### Schnellstart

```bash
# 1. Repo klonen
git clone git@github.com:the-SantosLab/naiceapp.git
cd naiceapp

# 2. Xcode öffnen
open HermesMobile.xcodeproj

# 3. Signing konfigurieren
# Team: GX89CS2T99 (SantosLab)
# Bundle: pro.naice.app

# 4. Build & Run (Cmd+R)
```

### OTA-Distribution

Gebuildete IPAs werden automatisch auf `agent.santoslab.de/naice-app/` bereitgestellt.
Die App prüft beim Start auf Updates und zeigt eine Benachrichtigung bei neuer Version.

---

## 🧩 Verwandte Projekte

- **[nAIce Agent](https://github.com/the-SantosLab/naice-agent)** – Der KI-Agent selbst
- **[nAIce WebUI](https://console.naice.app)** – Web-Oberfläche für den Agenten
- **[SantosLab](https://santoslab.de)** – Custom Software Entwicklung

---

## 📄 License

MIT © [SantosLab](https://santoslab.de) / Johannes Schaffer

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://github.com/the-SantosLab">SantosLab</a> · <a href="https://naice.app">nAIce.app</a></sub>
</div>