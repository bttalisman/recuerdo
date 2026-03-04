import Foundation

struct AzureSpeechConfig {
    let subscriptionKey: String
    let region: String

    static let shared: AzureSpeechConfig? = {
        guard let url = Bundle.main.url(forResource: "AzureSpeech", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let key = dict["SubscriptionKey"], !key.isEmpty,
              let region = dict["Region"], !region.isEmpty
        else { return nil }
        return AzureSpeechConfig(subscriptionKey: key, region: region)
    }()
}
