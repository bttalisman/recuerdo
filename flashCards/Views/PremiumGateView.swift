import SwiftUI

struct PremiumGateView: View {
    let feature: String
    let description: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text(feature)
                .font(.title2.bold())

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("Coming soon with Recuerdo Premium")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
    }
}
