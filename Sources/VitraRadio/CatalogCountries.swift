import SwiftUI

@MainActor final class CatalogCountries: ObservableObject {
    static let maximum = 8
    static var allCodes: [String] { Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 && $0.unicodeScalars.allSatisfy { (65...90).contains(Int($0.value)) } } }
    static func clean(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.uppercased() }).intersection(Set(allCodes))).sorted().prefix(maximum).map { $0 }
    }
    static func name(_ code: String) -> String { L10n.locale.localizedString(forRegionCode: code) ?? code }
    static func flag(_ code: String) -> String {
        String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
    @Published private(set) var codes: [String]
    @Published private(set) var needsSetup: Bool
    let suggested: String
    private let preferences: UserDefaults
    init(preferences: UserDefaults, preview: Bool = false, region: String? = Locale.current.region?.identifier) {
        self.preferences = preferences
        suggested = Self.clean([region ?? ""]).first ?? "BR"
        codes = preferences.stringArray(forKey: "catalogCountryCodes").map(Self.clean) ?? [suggested]
        needsSetup = (!preview || CommandLine.arguments.contains("--onboarding-preview")) && !preferences.bool(forKey: "catalogCountriesConfigured")
    }
    func toggle(_ code: String) {
        guard Self.allCodes.contains(code) else { return }
        if codes.contains(code) { codes.removeAll { $0 == code } }
        else if codes.count < Self.maximum { codes = Self.clean(codes + [code]) }
        preferences.set(codes, forKey: "catalogCountryCodes")
    }
    func useWorld() { codes = []; preferences.set(codes, forKey: "catalogCountryCodes") }
    func finishSetup() {
        preferences.set(codes, forKey: "catalogCountryCodes")
        preferences.set(true, forKey: "catalogCountriesConfigured")
        needsSetup = false
    }
    var summary: String {
        if codes.isEmpty { return L10n.tr("Mundo todo") }
        if codes.count == 1 { return Self.name(codes[0]) }
        return L10n.tr("\(codes.count) países")
    }
}

struct CatalogCountriesView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject private var countries: CatalogCountries
    @Environment(\.appPalette) private var palette
    var onboarding = false
    @State private var search = ""
    private var filtered: [String] {
        CatalogCountries.allCodes.filter { search.isEmpty || CatalogCountries.name($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search) }
            .sorted { CatalogCountries.name($0).localizedCompare(CatalogCountries.name($1)) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LanguagePicker()
            Label(onboarding ? L10n.tr("O mundo na sua frequência.") : L10n.tr("Países das suas rádios"), systemImage: "globe.americas.fill")
                .font(.system(size: 24, weight: .semibold))
            Text(onboarding ? L10n.tr("Sugerimos \(CatalogCountries.name(countries.suggested)) pela região deste Mac. Confirme ou adicione outros países para descobrir mais rádios.") : L10n.tr("Misture rádios de vários países no mesmo catálogo. A escolha fica salva neste Mac."))
                .font(.system(size: 12)).foregroundStyle(palette.muted)
            Text(L10n.tr("A sugestão usa a região do macOS, sem GPS ou consulta ao seu IP. Você pode mudá-la quando quiser."))
                .font(.system(size: 11)).foregroundStyle(palette.muted)
            HStack {
                Text(L10n.tr(countries.summary)).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.accent)
                Spacer()
                Button(L10n.tr("Mundo todo")) { countries.useWorld() }.buttonStyle(VitraButtonStyle())
            }
            if !countries.codes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(countries.codes, id: \.self) { code in
                            Button { countries.toggle(code) } label: {
                                Text("\(CatalogCountries.flag(code)) \(CatalogCountries.name(code))  ×")
                                    .font(.system(size: 11, weight: .medium)).padding(9)
                                    .background(palette.accent.opacity(0.12), in: Capsule()).contentShape(Capsule())
                            }.buttonStyle(.plain).foregroundStyle(palette.accent)
                        }
                    }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                TextField(L10n.tr("Buscar país…"), text: $search).textFieldStyle(.plain)
            }.padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filtered, id: \.self) { code in
                        Button { countries.toggle(code) } label: {
                            HStack(spacing: 10) {
                                Text(CatalogCountries.flag(code))
                                Text(CatalogCountries.name(code)).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Image(systemName: countries.codes.contains(code) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(countries.codes.contains(code) ? palette.accent : palette.muted)
                            }.padding(12).background(countries.codes.contains(code) ? palette.accent.opacity(0.08) : palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!countries.codes.contains(code) && countries.codes.count >= CatalogCountries.maximum)
                    }
                }
            }.frame(minHeight: 100, maxHeight: 250)
            HStack {
                Text(L10n.tr("Até \(CatalogCountries.maximum) países por vez · sem seleção: mundo todo")).font(.system(size: 10)).foregroundStyle(palette.muted)
                Spacer()
                if onboarding { Button(L10n.tr("Começar a ouvir")) { localization.select(localization.language); countries.finishSetup() }.buttonStyle(VitraButtonStyle()) }
            }
        }.padding(26).foregroundStyle(palette.text).background(palette.background)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.locale, localization.language.locale)
    }
}
