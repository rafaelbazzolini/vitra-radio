import Foundation
import SwiftUI

struct Station: Identifiable, Equatable {
    let id: String
    let name: String
    let frequency: String
    let genre: String
    let tagline: String
    let description: String
    let stream: URL
    let colors: [Color]
    let symbol: String
    var isLive = true
    var displayName: String { id == "welcome" ? L10n.tr(name) : name }
    var displayGenre: String { id == "welcome" || (id.hasPrefix("rb-") && genre == "Rádio ao vivo") ? L10n.tr(genre) : genre }
    var displayDescription: String {
        if id.hasPrefix("rb-"), tagline == "Sintonize uma nova companhia.", frequency != "WEB RADIO" {
            return L10n.tr("Ao vivo de \(frequency). Uma nova frequência para acompanhar o seu dia.")
        }
        return L10n.tr(description)
    }

    struct Saved: Codable, Equatable {
        let id: String
        let name: String
        let frequency: String
        let genre: String
        let tagline: String
        let description: String
        let stream: URL
        let symbol: String

        init(_ station: Station) {
            id = station.id; name = station.name; frequency = station.frequency
            genre = station.genre; tagline = station.tagline; description = station.description
            stream = station.stream; symbol = station.symbol
        }

        var station: Station? {
            guard ["https", "http"].contains(stream.scheme?.lowercased() ?? ""), stream.host != nil else { return nil }
            return Station(id: id, name: name, frequency: frequency, genre: genre, tagline: tagline,
                           description: description, stream: stream, colors: Station.catalogColors, symbol: symbol)
        }
    }

    static let catalogColors = [Color(hex: 0xA9D1B5), Color(hex: 0x466D60)]

    static let placeholder = Station(id: "welcome", name: "Escolha sua rádio", frequency: "AO VIVO", genre: "Seu momento, sua frequência",
        tagline: "O seu dia tem trilha.", description: "Encontre uma emissora no catálogo ou adicione seu próprio stream.",
        stream: URL(string: "https://example.invalid/no-station")!, colors: catalogColors, symbol: "antenna.radiowaves.left.and.right", isLive: false)
    // Fictional fixtures are available only in tests and screenshots. A fresh install has no stations.
    static let demo: [Station] = (0..<5).map { index in
        Station(id: "demo-\(index)", name: ["Aurora FM", "Horizonte", "Onda Jazz", "Estação Chill", "Vitra Sessions"][index],
            frequency: ["94,7 FM", "93,7 FM", "101,3 FM", "WEB RADIO", "100,7 FM"][index], genre: ["Contemporâneo", "Informação", "Jazz", "Lo-fi", "Instrumental"][index],
            tagline: "O seu dia tem trilha.", description: "Emissora fictícia para demonstração visual. Não é uma transmissão real.",
            stream: URL(string: "https://example.invalid/demo/\(index)")!, colors: catalogColors, symbol: "waveform")
    }
    static var all: [Station] {
        let fixture = CommandLine.arguments.contains { $0 == "--self-test" || $0 == "--render-previews" || $0.hasPrefix("--verify-") }
        return fixture ? demo : []
    }

}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

enum PlaybackState: Equatable {
    case idle, connecting, playing, paused, failed(L10n.Message)

    var label: String {
        switch self {
        case .idle: return L10n.tr("Pronto para ouvir")
        case .connecting: return L10n.tr("Conectando…")
        case .playing: return L10n.tr("Ao vivo")
        case .paused: return L10n.tr("Pausado")
        case .failed(let message): return L10n.tr(message)
        }
    }
    var isBusy: Bool { self == .connecting }
    var isPlaying: Bool { self == .playing }
}

enum MiniPlacement {
    static func clamped(_ origin: CGPoint, size: CGSize, screens: [CGRect]) -> CGPoint {
        guard let screen = screens.first(where: { $0.intersects(CGRect(origin: origin, size: size)) }) ?? screens.first else { return origin }
        return CGPoint(x: max(screen.minX + 8, min(origin.x, screen.maxX - size.width - 8)),
                       y: max(screen.minY + 8, min(origin.y, screen.maxY - size.height - 8)))
    }
}
