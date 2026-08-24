import SwiftUI

struct JournalCheckinCard: View {
    @State private var showCheckin = false
    @State private var selectedMood = "good"
    @State private var note = ""
    @State private var clarity = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book.closed.fill").font(.title3).foregroundColor(.ncSage)
                Text("Journal").font(.headline.weight(.semibold)).foregroundColor(.ncDark)
                Spacer()
                Text("\(NAJournalService.shared.todayCount) heute").font(.caption).foregroundColor(.ncMuted)
            }

            if showCheckin {
                // Mood selection
                HStack(spacing: 20) {
                    moodButton("good", "😊", "Gut")
                    moodButton("neutral", "😐", "Neutral")
                    moodButton("bad", "😔", "Nicht gut")
                }

                // Clarity slider
                HStack {
                    Text("Klarheit").font(.caption).foregroundColor(.ncMuted)
                    Slider(value: Binding(get: { Double(clarity) }, set: { clarity = Int($0) }), in: 1...10, step: 1)
                        .tint(.ncGreen)
                    Text("\(clarity)").font(.caption.weight(.bold)).foregroundColor(.ncDark).frame(width: 20)
                }

                // Note
                TextField("Was beschäftigt dich?", text: $note)
                    .padding(10).background(Color.ncPaper).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand, lineWidth: 0.5))

                HStack(spacing: 12) {
                    Button("Speichern") {
                        let t = note; let m = selectedMood; let c = clarity
                        note = ""; showCheckin = false
                        Task { await NAJournalService.shared.addEntry(text: t, mood: m, clarity: c) }
                    }
                    .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 10))

                    Button("Abbrechen") { showCheckin = false; note = "" }
                        .font(.subheadline).foregroundColor(.ncMuted)
                }
            } else {
                Button {
                    showCheckin = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(.ncGreen)
                        Text("Wie geht es dir?").font(.subheadline).foregroundColor(.ncDark)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.ncSand)
                    }
                }

                // Recent entries
                if !NAJournalService.shared.entries.isEmpty {
                    ForEach(NAJournalService.shared.entries.prefix(2)) { entry in
                        HStack(spacing: 10) {
                            Circle().fill(Color.ncSage.opacity(0.3)).frame(width: 6, height: 6)
                            Text(entry.text).font(.caption).foregroundColor(.ncMuted).lineLimit(1)
                            Spacer()
                            if let t = entry.created_at {
                                Text(String(t.prefix(10))).font(.system(size: 9)).foregroundColor(.ncSand)
                            }
                        }
                    }
                }
            }
        }
        .warmCard()
    }

    func moodButton(_ m: String, _ emoji: String, _ label: String) -> some View {
        Button {
            selectedMood = m
        } label: {
            VStack(spacing: 4) {
                Text(emoji).font(.title2)
                Text(label).font(.caption2).foregroundColor(selectedMood == m ? .ncGreen : .ncMuted)
            }
            .padding(10)
            .background(selectedMood == m ? Color.ncGreen.opacity(0.08) : Color.ncPaper, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedMood == m ? Color.ncGreen : Color.ncSand, lineWidth: selectedMood == m ? 1.5 : 0.5))
        }
    }
}