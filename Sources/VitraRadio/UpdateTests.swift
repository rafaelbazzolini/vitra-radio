import Foundation
import CryptoKit

enum UpdateTests {
    static func verifyPackage(archive: URL, checksums: URL, version: String) -> Int32 {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vitra-package-test-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            let target = root.appendingPathComponent("Vitra Radio.app")
            try fm.copyItem(at: Bundle.main.bundleURL, to: target)
            let before = try Data(contentsOf: target.appendingPathComponent("Contents/Info.plist"))
            let workspace = root.appendingPathComponent("download")
            try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
            let plan = try UpdateInstaller.prepare(archive: archive, checksums: String(contentsOf: checksums), version: version, target: target, workspace: workspace)
            try UpdateInstaller.validateBundle(plan.staged, version: version)
            guard try Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")) == before else {
                throw AppUpdateError(message: "O app instalado foi modificado durante a preparação.")
            }
            print("UPDATE_PACKAGE_OK: checksum, extração, assinatura, arquitetura e preparação do pacote real; app original preservado")
            return 0
        } catch {
            fputs("UPDATE_PACKAGE_FAILED: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor static func run() -> Int {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            if value { print("PASS: \(label)") } else { print("FAIL: \(label)"); failures += 1 }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        check(UpdateCheckSchedule.isDue(lastAttempt: nil, now: now), "Primeira verificação diária está disponível")
        check(!UpdateCheckSchedule.isDue(lastAttempt: now.addingTimeInterval(-86_399), now: now), "Não consulta novamente antes de 24 horas")
        check(UpdateCheckSchedule.isDue(lastAttempt: now.addingTimeInterval(-86_400), now: now), "Consulta ao completar 24 horas, inclusive após repouso")
        check(UpdateCheckSchedule.isDue(lastAttempt: now.addingTimeInterval(60), now: now), "Ajuste regressivo do relógio não bloqueia verificações")
        let domain = "com.vitra.radio.update-policy-tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let automatic = UpdateChecker(preferences: preferences)
        check(automatic.checkOnLaunch && automatic.checkDaily, "Verificações automáticas são habilitadas inicialmente")
        automatic.checkOnLaunch = false; automatic.checkDaily = false
        let disabled = UpdateChecker(preferences: preferences)
        check(!disabled.checkOnLaunch && !disabled.checkDaily, "Preferências desativadas persistem ao reabrir")
        disabled.checkDaily = true
        let dailyOnly = UpdateChecker(preferences: preferences)
        check(!dailyOnly.checkOnLaunch && dailyOnly.checkDaily, "Verificação diária é independente da abertura")
        preferences.set(now, forKey: "updatesLastAttempt")
        check(!UpdateCheckSchedule.isDue(lastAttempt: preferences.object(forKey: "updatesLastAttempt") as? Date, now: now), "Data persistida evita repetir consulta ao reiniciar")
        func rejects(_ label: String, _ operation: () throws -> Void) {
            do { try operation(); check(false, label) } catch { check(true, label) }
        }
        func release(_ tag: String = "v0.1.10", host: String = "github.com", prerelease: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "tag_name": tag, "draft": false, "prerelease": prerelease,
                "assets": [UpdateInstaller.assetName, "SHA256SUMS.txt"].map {
                    ["name": $0, "size": 123, "browser_download_url": "https://\(host)/\(UpdateChecker.repository)/releases/download/\(tag)/\($0)"] as [String: Any]
                }
            ])
        }
        do {
            check(try AppRelease.newer(from: release(), current: "0.1.9")?.version == "0.1.10", "Atualização compara versão numericamente (10 após 9)")
            check(try AppRelease.newer(from: release("v0.1.9"), current: "0.1.10") == nil, "Versão antiga nunca oferece downgrade")
            check(try AppRelease.newer(from: release(prerelease: true), current: "0.1.0") == nil, "Pré-release não entra no canal estável")
            rejects("Pacote de atualização fora do repositório é rejeitado") { _ = try AppRelease.newer(from: release(host: "example.com"), current: "0.1.0") }
            rejects("Caminhos que escapam do ZIP são rejeitados") { try UpdateInstaller.validateArchiveEntries("Vitra Radio.app/../../outside") }
            rejects("ZIP com caminho absoluto é rejeitado") { try UpdateInstaller.validateArchiveEntries("/tmp/Vitra Radio.app/file") }
            rejects("ZIP com link simbólico é rejeitado antes de extrair") { try UpdateInstaller.validateArchiveMetadata("lrwxr-xr-x 2.1 unx 20 bx 12 stor file") }
            rejects("ZIP excessivo é rejeitado antes de extrair") { try UpdateInstaller.validateArchiveMetadata("-rw-r--r-- 2.1 unx 300000001 bx 12 stor file") }
            try UpdateInstaller.validateArchiveEntries("Vitra Radio.app/Contents/MacOS/VitraRadio\n__MACOSX/Vitra Radio.app/._Contents")
            check(true, "ZIP aceita o app e metadados macOS previstos")
            let fm = FileManager.default
            let folder = fm.temporaryDirectory.appendingPathComponent("vitra-updater-tests-\(UUID().uuidString)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: folder) }
            let archive = folder.appendingPathComponent("archive.zip")
            let payload = Data("update-fixture".utf8)
            try payload.write(to: archive)
            let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            try UpdateInstaller.verifyChecksum(archive: archive, checksums: "\(hash)  \(UpdateInstaller.assetName)\n")
            check(true, "Checksum correto valida o pacote baixado")
            rejects("Pacote alterado nunca é instalado") { try UpdateInstaller.verifyChecksum(archive: archive, checksums: "\(String(repeating: "0", count: 64))  \(UpdateInstaller.assetName)") }
            let target = folder.appendingPathComponent("Vitra Radio.app")
            let staged = folder.appendingPathComponent(".vitra-update-test.app")
            for (directory, text) in [(target, "old"), (staged, "new")] {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(text.utf8).write(to: directory.appendingPathComponent("version"))
            }
            let preferences = folder.appendingPathComponent("preferences.json")
            try Data("favorites-unchanged".utf8).write(to: preferences)
            rejects("Falha ao reabrir aciona recuperação da versão anterior") {
                try UpdateInstaller.replaceAndLaunch(target: target, staged: staged) { _ in throw AppUpdateError(message: "simulated launch failure") }
            }
            check(try String(contentsOf: target.appendingPathComponent("version")) == "old", "Recuperação mantém o app antigo no endereço instalado")
            try UpdateInstaller.replaceAndLaunch(target: target, staged: staged) { app in
                guard try String(contentsOf: app.appendingPathComponent("version")) == "new" else { throw AppUpdateError(message: "wrong version") }
            }
            check(try String(contentsOf: target.appendingPathComponent("version")) == "new", "Troca atômica abre a nova versão no mesmo endereço")
            check(try String(contentsOf: preferences) == "favorites-unchanged", "Atualização não modifica as preferências do usuário")
            check(try String(contentsOf: staged.appendingPathComponent("version")) == "old", "Cópia anterior é preservada até a nova versão abrir")
        } catch { check(false, "Verificação do atualizador: \(error.localizedDescription)") }
        return failures
    }
}
