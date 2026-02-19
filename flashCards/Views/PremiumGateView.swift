import SwiftUI

struct PremiumGateView: View {
    let feature: String
    let description: String
    @Environment(\.dismiss) private var dismiss
    var premiumManager = PremiumManager.shared
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if showSuccess {
                successView
            } else {
                purchaseView
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: premiumManager.isPurchased) { _, purchased in
            if purchased {
                showSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }

    private var purchaseView: some View {
        VStack(spacing: 24) {
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

            VStack(spacing: 12) {
                Button {
                    Task { await premiumManager.purchase() }
                } label: {
                    HStack {
                        if premiumManager.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Unlock Premium — \(premiumManager.displayPrice)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(premiumManager.isLoading)
                .padding(.horizontal, 32)

                Button {
                    Task { await premiumManager.restorePurchases() }
                } label: {
                    Text("Restore Purchase")
                        .font(.subheadline)
                }
                .disabled(premiumManager.isLoading)
            }

            if let error = premiumManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Not Now") {
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Premium Unlocked!")
                .font(.title2.bold())

            Text("All features are now available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
