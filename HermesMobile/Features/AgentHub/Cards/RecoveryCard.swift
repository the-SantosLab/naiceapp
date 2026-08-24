import SwiftUI

struct RecoveryCard: View {
    let whoop: NAWhoop

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Recovery Score with progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Recovery").font(.subheadline).foregroundColor(.ncMuted)
                    Spacer()
                    Text("\(whoop.recoveryScore)%")
                        .font(.title3.weight(.bold))
                        .foregroundColor(recoveryColor(whoop.recoveryScore))
                }
                ProgressView(value: Double(whoop.recoveryScore), total: 100)
                    .tint(recoveryColor(whoop.recoveryScore))
            }

            // Key metrics
            HStack(spacing: 0) {
                wm("heart.fill", "\(whoop.restingHeartRate)", "Ruhepuls")
                wm("waveform.path.ecg", "\(Int(whoop.hrv))ms", "HRV")
                wm("bolt.fill", String(format: "%.1f", whoop.strain), "Strain")
                wm("heart.circle", "\(whoop.avgHeartRate)", "Puls Ø")
            }

            Divider().foregroundColor(.ncSand.opacity(0.3))

            // Additional metrics row
            HStack(spacing: 0) {
                if whoop.spo2 > 0 { wm("drop.fill", "\(Int(whoop.spo2))%", "SpO2") }
                wm("lungs.fill", "\(Int(whoop.respiratoryRate))", "Atmung")
                if whoop.skinTemp > 0 { wm("thermometer", String(format: "%.1f", whoop.skinTemp), "Temp") }
            }

            // Last sync
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.caption2).foregroundColor(.ncMuted)
                Text("Letzter Sync: \(whoop.lastSyncRelative)").font(.system(size: 10)).foregroundColor(.ncMuted)
                Spacer()
            }
        }
    }
}