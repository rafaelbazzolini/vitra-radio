import SwiftUI

enum RadioMood: String, CaseIterable, Codable {
    case workout = "Treino", work = "Trabalho", meditation = "Meditação"
    static let suggestions: [(RadioMood, Station)] = [
        (.workout, Station(id: "mood-ffh-workout", name: "FFH Workout", frequency: "DE · WEB RADIO", genre: "Dance · EDM", tagline: "O seu dia tem trilha.", description: "FFH Workout", stream: URL(string: "https://mp3.ffh.de/ffhchannels/hqworkout.mp3")!, colors: Station.catalogColors, symbol: "waveform")),
        (.workout, Station(id: "mood-antenne-workout", name: "ANTENNE BAYERN Workout Mix", frequency: "DE · WEB RADIO", genre: "Dance · Pop", tagline: "O seu dia tem trilha.", description: "ANTENNE BAYERN Workout Mix", stream: URL(string: "https://stream.antenne.de/workout-hits/stream/mp3")!, colors: Station.catalogColors, symbol: "waveform")),
        (.workout, Station(id: "mood-hotmix-workout", name: "Hotmix Sport Workout", frequency: "FR · WEB RADIO", genre: "Dance · Workout", tagline: "O seu dia tem trilha.", description: "Hotmix Sport Workout", stream: URL(string: "https://streaming.hotmixradio.com/hotmix-sport-plus-en-mp3")!, colors: Station.catalogColors, symbol: "waveform")),
        (.work, Station(id: "mood-groovesalad", name: "SomaFM Groove Salad", frequency: "US · WEB RADIO", genre: "Ambient · Downtempo", tagline: "O seu dia tem trilha.", description: "SomaFM Groove Salad", stream: URL(string: "https://ice2.somafm.com/groovesalad-128-mp3")!, colors: Station.catalogColors, symbol: "waveform")),
        (.meditation, Station(id: "mood-dronezone", name: "SomaFM Drone Zone", frequency: "US · WEB RADIO", genre: "Ambient · Drone", tagline: "O seu dia tem trilha.", description: "SomaFM Drone Zone", stream: URL(string: "https://ice2.somafm.com/dronezone-128-mp3")!, colors: Station.catalogColors, symbol: "waveform")),
    ]
}

struct RadioMoodMenu: View {
    @EnvironmentObject private var radio: RadioPlayer
    let station: Station
    var body: some View {
        Menu {
            Text(L10n.tr("Categorias neste dispositivo"))
            ForEach(RadioMood.allCases, id: \.self) { mood in
                Button { radio.toggleMood(mood, station: station) } label: {
                    Label(L10n.tr(mood.rawValue), systemImage: radio.hasMood(mood, station: station) ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: { Image(systemName: "tag").frame(width: 24, height: 24).contentShape(Rectangle()) }
        .menuStyle(.borderlessButton).fixedSize().help(L10n.tr("Vincular a categorias"))
    }
}
