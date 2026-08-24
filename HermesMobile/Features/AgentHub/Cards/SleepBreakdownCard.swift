import SwiftUI

struct SleepBreakdownCard: View {
    let whoop: NAWhoop

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Schlaf").font(.subheadline).foregroundColor(.ncMuted)
                Spacer()
                Text(String(format: "%.1fh", whoop.sleepHours))
                    .font(.subheadline.weight(.bold)).foregroundColor(.ncDark)
                if whoop.sleepEfficiency > 0 {
                    Text("\(Int(whoop.sleepEfficiency))%").font(.caption).foregroundColor(.ncSage)
                }
            }

            if whoop.phases.remHours > 0 || whoop.phases.lightHours > 0 {
                let total = max(whoop.phases.deepHours + whoop.phases.remHours + whoop.phases.lightHours + whoop.phases.awakeHours, 0.1)

                GeometryReader { geo in
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.ncDark)
                            .frame(width: geo.size.width * CGFloat(whoop.phases.deepHours / total))
                            .overlay(Text("D").font(.system(size: 7)).foregroundColor(.white))
                        Rectangle().fill(Color.ncGreen)
                            .frame(width: geo.size.width * CGFloat(whoop.phases.remHours / total))
                            .overlay(Text("R").font(.system(size: 7)).foregroundColor(.white))
                        Rectangle().fill(Color.ncSand.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(whoop.phases.lightHours / total))
                            .overlay(Text("L").font(.system(size: 7)).foregroundColor(.white))
                        Rectangle().fill(Color.ncRed.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(whoop.phases.awakeHours / total))
                            .overlay(Text("A").font(.system(size: 7)).foregroundColor(.white))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 14)

                HStack(spacing: 8) {
                    legend("Deep", Color.ncDark)
                    legend("REM", Color.ncGreen)
                    legend("Light", Color.ncSand.opacity(0.5))
                    legend("Awake", Color.ncRed.opacity(0.3))
                    Spacer()
                    if whoop.sleepPerformance > 0 {
                        Text("Perf \(Int(whoop.sleepPerformance))%")
                            .font(.system(size: 9)).foregroundColor(.ncMuted)
                    }
                    if let p7 = whoop.phases7day, p7.totalHours > 0 {
                        Text("7d Ø \(String(format: "%.1f", p7.totalHours))h")
                            .font(.system(size: 9)).foregroundColor(.ncSage)
                    }
                }
            } else if whoop.sleepPerformance > 0 {
                Text("Performance: \(Int(whoop.sleepPerformance))%")
                    .font(.system(size: 9)).foregroundColor(.ncMuted)
            }
        }
    }
}