import SwiftUI

struct CatalogView: View {
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var countries: CatalogCountries
    @State private var showingCountries = false
    @ObservedObject var catalog: RadioCatalog
    @State private var query = CatalogQuery()
    @State private var retry = 0
    private var searchID: String { "\(countries.codes.joined(separator: ","))|\(query.name)|\(retry)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MAIS FREQUÊNCIAS. NOVAS COMPANHIAS.").font(.system(size: 9, weight: .bold)).tracking(1.7).foregroundStyle(palette.muted)
                    Text("Todas as rádios.").font(.system(size: 29, weight: .semibold)).tracking(-1.1)
                    Text("Encontre uma emissora para ouvir agora ou guardar nas favoritas.")
                        .font(.system(size: 12)).foregroundStyle(palette.muted)
                }
                HStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                        TextField("Buscar pelo nome da rádio…", text: $query.name)
                            .textFieldStyle(.plain).font(.system(size: 13)).accessibilityLabel("Buscar em todas as rádios")
                        if !query.name.isEmpty {
                            Button { query.name = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(palette.muted).help("Limpar busca")
                        }
                    }.padding(14).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    Button { showingCountries = true } label: {
                        Label(countries.summary, systemImage: "globe").font(.system(size: 12, weight: .semibold))
                    }.buttonStyle(VitraButtonStyle())
                }
                HStack {
                    Text(query.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Populares · \(countries.summary)" : "Resultados da busca")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if !catalog.stations.isEmpty {
                        Text("\(catalog.stations.count) EMISSORAS").font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1).foregroundStyle(palette.muted)
                    }
                }
                if catalog.isLoading && catalog.stations.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Buscando suas próximas rádios…").font(.system(size: 12)).foregroundStyle(palette.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 65)
                } else if catalog.stations.isEmpty && catalog.error == nil {
                    VStack(spacing: 11) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 30, weight: .light)).foregroundStyle(palette.accent)
                        Text("Nenhuma rádio encontrada").font(.headline)
                        Text("Experimente outro nome ou procure no mundo todo.").font(.system(size: 12)).foregroundStyle(palette.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 45)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)], spacing: 13) {
                    ForEach(catalog.stations) { StationCard(station: $0) }
                }
                if let error = catalog.error {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").foregroundStyle(palette.muted)
                        Text(error).font(.system(size: 12)).foregroundStyle(palette.muted)
                        Spacer()
                        Button("Tentar novamente") {
                            if catalog.stations.isEmpty { retry += 1 }
                            else { Task { await catalog.loadMore() } }
                        }.buttonStyle(.bordered).tint(palette.accent)
                    }.padding(16).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if catalog.hasMore {
                    Button {
                        Task { await catalog.loadMore() }
                    } label: {
                        HStack(spacing: 9) {
                            if catalog.isLoading { ProgressView().controlSize(.small) }
                            Text(catalog.isLoading ? "Carregando…" : "Carregar mais rádios").font(.system(size: 12, weight: .medium))
                            if !catalog.isLoading { Image(systemName: "chevron.down").font(.system(size: 10)) }
                        }.padding(.horizontal, 20).padding(.vertical, 12)
                            .background(palette.accent.opacity(0.10), in: Capsule()).foregroundStyle(palette.accent)
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).disabled(catalog.isLoading).frame(maxWidth: .infinity)
                }
                HStack(spacing: 4) {
                    Text("Catálogo")
                    Link("Radio Browser", destination: URL(string: "https://www.radio-browser.info/")!)
                }.font(.system(size: 10)).foregroundStyle(palette.muted).tint(palette.muted)
            }.padding(.horizontal, 30).padding(.top, 47).padding(.bottom, 28)
        }.scrollIndicators(.hidden)
            .sheet(isPresented: $showingCountries) {
                VStack { CatalogCountriesView(); Button("Concluir") { showingCountries = false }.buttonStyle(VitraButtonStyle()).padding(.bottom, 20) }
                    .frame(width: 580, height: 640).background(palette.background)
            }
            .task(id: searchID) { await catalog.search(CatalogQuery(name: query.name, countryCodes: countries.codes)) }
    }
}
