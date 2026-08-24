import SwiftUI
import SwiftData

struct IdeasCard: View {
    @Environment(\.modelContext) var mc
    @Binding var showIdea: Bool
    @Binding var newIdea: String
    let ideas: [NAIdea]
    let onSave: () async -> Void

    var body: some View {
        NAIceSectionLabel(icon: "square.and.pencil", title: "QuickLog & Ideen")
        QuickLogCard(mc: mc)

        if showIdea {
            HStack(spacing: 8) {
                TextField("Idee eingeben...", text: $newIdea)
                    .padding(10)
                    .background(Color.ncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ncSand, lineWidth: 0.5))
                Button("Speichern") {
                    Task { await onSave() }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.ncGreen, in: RoundedRectangle(cornerRadius: 9))
            }.warmCard()
        } else {
            Button("Idee festhalten") { showIdea = true }
                .font(.caption).foregroundColor(.ncSage).padding(.horizontal, 4)
        }

        ForEach(Array(ideas.prefix(3))) { idea in
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill").font(.caption).foregroundColor(.ncGold)
                Text(idea.text).font(.subheadline).foregroundColor(.ncDark)
                Spacer()
                Text(idea.createdAt, style: .relative).font(.caption2).foregroundColor(.ncMuted)
            }.warmCard()
        }
    }
}