import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case portuguese = "pt-BR", english = "en"
    var id: String { rawValue }
    var name: String { self == .portuguese ? "Português (Brasil)" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
    static func suggested(_ preferred: [String]) -> Self {
        for code in preferred {
            if code.lowercased().hasPrefix("pt") { return .portuguese }
            if code.lowercased().hasPrefix("en") { return .english }
        }
        return .portuguese
    }
}

/// The app preference is independent of the radio countries and the system language.
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    @Published private(set) var language: AppLanguage = .portuguese
    private var preferences: UserDefaults?
    func configure(preferences: UserDefaults, preferred: [String] = Locale.preferredLanguages) {
        self.preferences = preferences
        set(AppLanguage(rawValue: preferences.string(forKey: "interfaceLanguage") ?? "") ?? .suggested(preferred), persist: false)
    }
    func select(_ language: AppLanguage) { set(language, persist: true) }
    private func set(_ value: AppLanguage, persist: Bool) {
        L10n.language = value
        language = value
        if persist { preferences?.set(value.rawValue, forKey: "interfaceLanguage") }
    }
}

/// Literal interpolation keeps station names and user-entered text out of the translation keys.
/// Dynamic strings are only looked up exactly, without changing persisted values.
enum L10n {
    private static let lock = NSLock()
    private static var selected: AppLanguage = .portuguese
    static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set { lock.lock(); selected = newValue; lock.unlock() }
    }
    static var locale: Locale { language.locale }
    static let english: [String: String] = {
        guard let url = Bundle.main.url(forResource: "en", withExtension: "json", subdirectory: "Languages"),
              let data = try? Data(contentsOf: url), let strings = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return strings
    }()
    @_disfavoredOverload static func tr(_ value: String) -> String {
        language == .english ? (english[value] ?? value) : value
    }
    static func tr(_ message: Message) -> String {
        let template = tr(message.key)
        if message.arguments.isEmpty { return template }
        let parts = template.components(separatedBy: "%@")
        guard parts.count == message.arguments.count + 1 else { return message.original }
        return zip(parts.dropLast(), message.arguments).map { $0 + $1 }.joined() + (parts.last ?? "")
    }
    struct Message: Equatable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let key: String
        let arguments: [String]
        var original: String {
            let parts = key.components(separatedBy: "%@")
            return zip(parts.dropLast(), arguments).map { $0 + $1 }.joined() + (parts.last ?? "")
        }
        init(stringLiteral value: String) { key = value; arguments = [] }
        init(stringInterpolation value: StringInterpolation) { key = value.key; arguments = value.arguments }
        struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []
            init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
            mutating func appendLiteral(_ literal: String) { key += literal }
            mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append(String(describing: value)) }
        }
    }
    static func date(_ value: Date) -> String {
        value.formatted(.dateTime.locale(locale).day().month(.abbreviated).year().hour().minute())
    }
}

struct LanguagePicker: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.appPalette) private var palette
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "globe").foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("Idioma")).font(.system(size: 13, weight: .semibold))
                Text(L10n.tr("O idioma não altera os países das rádios.")).font(.system(size: 10)).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 8)
            Picker(L10n.tr("Idioma"), selection: Binding(get: { localization.language }, set: { localization.select($0) })) {
                ForEach(AppLanguage.allCases) { language in Text(language.name).tag(language) }
            }.labelsHidden().frame(width: 180)
        }.padding(14).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
