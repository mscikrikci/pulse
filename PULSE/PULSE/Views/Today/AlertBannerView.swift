import SwiftUI

struct AlertBannerView: View {
    let alerts: [SafeZoneAlert]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(alerts) { alert in
                HStack(spacing: 12) {
                    Image(systemName: alert.status == .alert ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(alert.status == .alert ? .red : .orange)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(alert.metric) \(alert.status == .alert ? "ALERT" : "WARNING")")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(alert.status == .alert ? .red : .orange)
                        Text("\(alert.current) · baseline \(alert.baseline) · \(alert.delta)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(alert.status == .alert ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                )
            }
        }
    }
}
