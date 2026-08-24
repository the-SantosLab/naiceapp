import SwiftUI

struct WorkoutScrollRow: View {
    let workouts: [NAWorkout]
    let whoop: NAWhoop

    var body: some View {
        if workouts.isEmpty { EmptyView() }
        let recent = Array(workouts.prefix(3))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(recent) { wo in
                    VStack(spacing: 6) {
                        Image(systemName: wo.sportIcon).font(.title2).foregroundColor(.ncGreen)
                        Text(wo.sport.capitalized).font(.system(size: 9)).foregroundColor(.ncMuted)
                        Text("\(wo.durationMinutes)min").font(.caption.weight(.semibold)).foregroundColor(.ncDark)
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill").font(.system(size: 7)).foregroundColor(.ncGold)
                            Text(String(format: "%.1f", wo.strain)).font(.system(size: 9)).foregroundColor(.ncDark)
                        }
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill").font(.system(size: 7)).foregroundColor(.ncRed)
                            Text("\(wo.avgHr)").font(.system(size: 9)).foregroundColor(.ncMuted)
                        }
                    }
                    .padding(10)
                    .background(Color.ncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ncSand.opacity(0.4)))
                }
                if workouts.count > 3 {
                    NavigationLink(destination: WorkoutsDetailView(whoop: whoop)) {
                        VStack(spacing: 6) {
                            Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundColor(.ncSage)
                            Text("Alle \(workouts.count)").font(.caption.weight(.semibold)).foregroundColor(.ncDark)
                            Text("Anzeigen →").font(.system(size: 8)).foregroundColor(.ncSage)
                        }.padding(10)
                    }
                }
            }.padding(.horizontal, 4)
        }
    }
}