import SwiftUI

struct ProjectSupport: Decodable {
    let donationURL: String?
    var destination: URL? {
        guard let donationURL, let url = URL(string: donationURL), url.scheme == "https", let host = url.host,
              !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static var current: ProjectSupport {
        guard let file = Bundle.main.url(forResource: "support", withExtension: "json"),
              let data = try? Data(contentsOf: file), let config = try? JSONDecoder().decode(ProjectSupport.self, from: data) else {
            return ProjectSupport(donationURL: nil)
        }
        return config
    }
}

struct SupportProjectButton: View {
    @Environment(\.appPalette) private var palette
    @State private var showingSupport = false
    var body: some View {
        Button { showingSupport = true } label: {
            Label("Apoiar", systemImage: "heart").font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 8)
                .foregroundStyle(palette.muted).contentShape(Capsule())
        }.buttonStyle(.plain).help("Apoiar o desenvolvimento do Vitra Radio")
            .sheet(isPresented: $showingSupport) {
                SupportProjectView().frame(width: 500, height: 350)
                    .overlay(alignment: .topTrailing) {
                        Button { showingSupport = false } label: { Image(systemName: "xmark").padding(14).contentShape(Rectangle()) }
                            .buttonStyle(.plain).padding(6)
                    }
            }
    }
}

struct SupportProjectView: View {
    @Environment(\.appPalette) private var palette
    private let support = ProjectSupport.current
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "heart.circle").font(.system(size: 42, weight: .light)).foregroundStyle(palette.accent)
            Text("Ajude o Vitra a continuar tocando.").font(.system(size: 25, weight: .semibold))
            Text("Se o Vitra faz parte do seu dia, uma contribuição voluntária ajuda a manter o projeto e desenvolver novas funções.")
                .font(.system(size: 13)).foregroundStyle(palette.muted).lineSpacing(4)
            if let destination = support.destination {
                Link(destination: destination) { Label("Fazer uma contribuição", systemImage: "arrow.up.right") }
                    .buttonStyle(VitraButtonStyle())
                Text("Você escolhe o valor. O pagamento é feito no site do provedor; o Vitra não recebe dados de cartão.")
                    .font(.system(size: 11)).foregroundStyle(palette.muted)
            } else {
                Text("O canal de doações ainda está sendo preparado.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(palette.accent)
            }
            Spacer(minLength: 0)
        }.padding(30).foregroundStyle(palette.text).background(palette.background)
    }
}
