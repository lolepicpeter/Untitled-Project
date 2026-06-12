import Foundation

struct DocumentTemplateSettings: Codable, Equatable {
    static let defaultFooterText = "Printed from MyInvoice"

    private static let footerTextKey = "documentTemplateSettings.footerText"
    private static let showsSignatureLinesKey = "documentTemplateSettings.showsSignatureLines"

    var footerText: String
    var showsSignatureLines: Bool

    static func load(userDefaults: UserDefaults = .standard) -> DocumentTemplateSettings {
        let footerText = userDefaults.string(forKey: footerTextKey) ?? defaultFooterText
        let showsSignatureLines = userDefaults.object(forKey: showsSignatureLinesKey) as? Bool ?? true
        return DocumentTemplateSettings(
            footerText: footerText,
            showsSignatureLines: showsSignatureLines
        )
    }

    func save(userDefaults: UserDefaults = .standard) {
        userDefaults.set(footerText.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.footerTextKey)
        userDefaults.set(showsSignatureLines, forKey: Self.showsSignatureLinesKey)
    }

    static func reset(userDefaults: UserDefaults = .standard) -> DocumentTemplateSettings {
        userDefaults.removeObject(forKey: footerTextKey)
        userDefaults.removeObject(forKey: showsSignatureLinesKey)
        return load(userDefaults: userDefaults)
    }
}
