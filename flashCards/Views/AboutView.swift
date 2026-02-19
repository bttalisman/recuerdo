import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("Chispa")
                        .font(.largeTitle.bold())
                    Text("Spanish Flashcards")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Version 1.0")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section("Data Sources") {
                creditRow(
                    name: "Tatoeba",
                    url: "https://tatoeba.org",
                    description: "Example sentences and translations",
                    license: "CC BY 2.0 FR"
                )

                creditRow(
                    name: "Anki Shared Decks",
                    url: "https://ankiweb.net/shared/decks",
                    description: "Core vocabulary word list",
                    license: nil
                )
            }

            Section("Translation Verification") {
                creditRow(
                    name: "DeepL",
                    url: "https://www.deepl.com",
                    description: "Used to cross-check translation accuracy",
                    license: nil
                )
            }

            Section("Spaced Repetition") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SM-2 Algorithm")
                        .font(.subheadline.bold())
                    Text("Based on the SuperMemo 2 algorithm by Piotr Wozniak, as popularized by Anki.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Made with care for language learners everywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(name: String, url: String, description: String, license: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline.bold())
                Spacer()
                if let license {
                    Text(license)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(url, destination: URL(string: url)!)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
