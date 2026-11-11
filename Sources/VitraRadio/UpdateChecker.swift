import AppKit
import UserNotifications

@MainActor final class UpdateChecker: NSObject, UNUserNotificationCenterDelegate {
    static let repository = "rafaelbazzolini/vitra-radio"
    private var timer: Timer?
    private var checking = false
    private var notice: String?
    private let preferences: UserDefaults
    init(preferences: UserDefaults) { self.preferences = preferences }
    func start() {
        UNUserNotificationCenter.current().delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.check() } }
        check()
    }
    func stop() { timer?.invalidate(); timer = nil }
    func check(manual: Bool = false) {
        guard !checking else { return }; checking = true
        Task { @MainActor in
            defer { checking = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
                request.setValue("VitraRadio", forHTTPHeaderField: "User-Agent"); request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let status = response as? HTTPURLResponse, status.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = json["tag_name"] as? String,
                      json["draft"] as? Bool != true, json["prerelease"] as? Bool != true else {
                    if manual { message("Ainda não há uma versão nova disponível.") }; return
                }
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
                let next = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard next.compare(current, options: .numeric) == .orderedDescending else { if manual { message("O Vitra Radio está atualizado.") }; return }
                guard manual || notice != tag else { return }; notice = tag
                if preferences.bool(forKey: "updateNotifications") {
                    let content = UNMutableNotificationContent()
                    content.title = "Vitra Radio \(tag) disponível"; content.body = "Abra a nova versão na página de atualizações."
                    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "vitra-update", content: content, trigger: nil))
                }
                let alert = NSAlert(); alert.messageText = "Vitra Radio \(tag) disponível"
                alert.informativeText = "Uma atualização publicada a partir do main está pronta. Você escolhe quando baixar e instalar."
                alert.addButton(withTitle: "Ver atualização"); alert.addButton(withTitle: "Depois")
                if alert.runModal() == .alertFirstButtonReturn { openRelease() }
            } catch { if manual { message("Não foi possível verificar as atualizações. Tente novamente quando houver conexão.") } }
        }
    }
    func enableNotifications() {
        Task { @MainActor in
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
            preferences.set(granted, forKey: "updateNotifications")
            message(granted ? "Notificações de atualização ativadas." : "Você pode permitir notificações nos Ajustes do Sistema. O aviso dentro do app continua disponível.")
        }
    }
    private func message(_ text: String) { let alert = NSAlert(); alert.messageText = text; alert.runModal() }
    private func openRelease() { NSWorkspace.shared.open(URL(string: "https://github.com/\(Self.repository)/releases/latest")!) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async { await MainActor.run { self.openRelease() } }
}
