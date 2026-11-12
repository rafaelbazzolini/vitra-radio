import Foundation
import CryptoKit
import Darwin

struct AppUpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct UpdateInstallPlan: Codable {
    let target: URL
    let staged: URL
    let parentPID: Int32
    let version: String
    let workspace: URL
}

enum UpdateInstaller {
    static let assetName = "VitraRadio-macOS-universal.zip"
    static let bundleID = "com.vitra.radio"

    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppUpdateError(message: L10n.tr("Não foi possível validar ou preparar a atualização.")) }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func verifyChecksum(archive: URL, checksums: String) throws {
        let matches = checksums.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[1].replacingOccurrences(of: "*", with: "") == assetName else { return nil }
            return String(fields[0]).lowercased()
        }
        guard matches.count == 1, matches[0].range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw AppUpdateError(message: L10n.tr("A release não contém um checksum válido para o app."))
        }
        let file = try FileHandle(forReadingFrom: archive)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == matches[0] else { throw AppUpdateError(message: L10n.tr("O pacote está incompleto ou foi alterado. Tente atualizar novamente.")) }
    }

    static func validateArchiveEntries(_ listing: String) throws {
        let paths = listing.split(whereSeparator: \.isNewline)
        guard !paths.isEmpty, paths.count <= 10_000 else { throw AppUpdateError(message: L10n.tr("Pacote de atualização inválido.")) }
        for path in paths {
            let parts = path.split(separator: "/")
            guard !path.hasPrefix("/"), !path.contains("\\"), !parts.contains(".."),
                  parts.first == "Vitra Radio.app" || parts.first == "__MACOSX" else {
                throw AppUpdateError(message: L10n.tr("O pacote contém caminhos inválidos."))
            }
        }
    }

    static func validateArchiveMetadata(_ listing: String) throws {
        var size = 0
        for line in listing.split(whereSeparator: \.isNewline) {
            guard let first = line.first, "-dlbcps".contains(first) else { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard (first == "-" || first == "d"), fields.count >= 4, let bytes = Int(fields[3]), bytes >= 0,
                  bytes <= 300_000_000 - size else {
                throw AppUpdateError(message: L10n.tr("O pacote contém links, arquivos especiais ou excede o tamanho permitido."))
            }
            size += bytes
        }
    }

    static func validateBundle(_ app: URL, version: String? = nil) throws {
        let fm = FileManager.default
        let values = try app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard app.isFileURL, app.pathExtension == "app", values.isDirectory == true, values.isSymbolicLink != true,
              let data = fm.contents(atPath: app.appendingPathComponent("Contents/Info.plist").path),
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleExecutable"] as? String == "VitraRadio",
              version == nil || info["CFBundleShortVersionString"] as? String == version,
              fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/VitraRadio").path) else {
            throw AppUpdateError(message: L10n.tr("O pacote não corresponde à versão esperada do Vitra Radio."))
        }
        // The native app has no symlinks. Reject links before launching a downloaded executable.
        guard let files = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey]) else {
            throw AppUpdateError(message: L10n.tr("Não foi possível inspecionar o pacote."))
        }
        var total = 0
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw AppUpdateError(message: L10n.tr("O pacote contém links não permitidos.")) }
            total += values.fileSize ?? 0
            guard total <= 300_000_000 else { throw AppUpdateError(message: "O pacote excede o tamanho permitido.") }
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let architectures = try run("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/VitraRadio").path])
        #if arch(arm64)
        let required = "arm64"
        #else
        let required = "x86_64"
        #endif
        guard architectures.split(separator: " ").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).contains(required) else {
            throw AppUpdateError(message: L10n.tr("Esta atualização não é compatível com o processador deste Mac."))
        }
    }

    static func prepare(archive: URL, checksums: String, version: String, target: URL, workspace: URL) throws -> UpdateInstallPlan {
        let fm = FileManager.default
        try validateBundle(target)
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path), !target.path.hasPrefix("/Volumes/") else {
            throw AppUpdateError(message: L10n.tr("Mova o Vitra Radio para Aplicativos em uma pasta com permissão de escrita antes de atualizar."))
        }
        try verifyChecksum(archive: archive, checksums: checksums)
        let listing = try run("/usr/bin/unzip", ["-Z1", archive.path])
        try validateArchiveEntries(listing)
        try validateArchiveMetadata(run("/usr/bin/unzip", ["-Z", "-l", archive.path]))
        let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let source = extracted.appendingPathComponent("Vitra Radio.app")
        try validateBundle(source, version: version)
        let staged = parent.appendingPathComponent(".vitra-update-\(UUID().uuidString).app", isDirectory: true)
        do {
            try fm.copyItem(at: source, to: staged)
            try validateBundle(staged, version: version)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        return UpdateInstallPlan(target: target, staged: staged, parentPID: getpid(), version: version, workspace: workspace)
    }

    static func startHelper(_ plan: UpdateInstallPlan) throws {
        let file = plan.workspace.appendingPathComponent("install.json")
        try JSONEncoder().encode(plan).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let helper = Process()
        helper.executableURL = plan.staged.appendingPathComponent("Contents/MacOS/VitraRadio")
        helper.arguments = ["--install-update", file.path]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }

    /// Atomic swap keeps either the old or the new bundle at its installed location.
    /// A launch failure swaps the original app back before returning the error.
    static func replaceAndLaunch(target: URL, staged: URL, launch: (URL) throws -> Void) throws {
        guard renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, target.path, UInt32(RENAME_SWAP)) == 0 else {
            throw AppUpdateError(message: L10n.tr("Não foi possível substituir o aplicativo. A versão anterior foi mantida."))
        }
        do { try launch(target) }
        catch {
            let restored = renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, target.path, UInt32(RENAME_SWAP)) == 0
            if !restored { throw AppUpdateError(message: L10n.tr("A reabertura falhou. A cópia anterior foi preservada em \(staged.path).")) }
            throw error
        }
    }

    static func runHelper(planURL: URL) -> Int32 {
        let fm = FileManager.default
        do {
            let plan = try JSONDecoder().decode(UpdateInstallPlan.self, from: Data(contentsOf: planURL))
            guard plan.parentPID > 1, plan.parentPID != getpid(),
                  plan.staged.deletingLastPathComponent() == plan.target.deletingLastPathComponent(),
                  plan.staged.lastPathComponent.hasPrefix(".vitra-update-"),
                  plan.workspace == planURL.deletingLastPathComponent() else {
                throw AppUpdateError(message: L10n.tr("Plano de atualização inválido."))
            }
            try validateBundle(plan.staged, version: plan.version)
            try validateBundle(plan.target)
            for _ in 0..<300 {
                if kill(plan.parentPID, 0) != 0 && errno == ESRCH { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard kill(plan.parentPID, 0) != 0 && errno == ESRCH else {
                throw AppUpdateError(message: L10n.tr("O Vitra Radio ainda está aberto. A versão instalada foi mantida."))
            }
            try replaceAndLaunch(target: plan.target, staged: plan.staged) { target in
                _ = try run("/usr/bin/open", ["-n", target.path])
            }
            try? fm.removeItem(at: plan.staged) // Old bundle, after a successful launch.
            try? fm.removeItem(at: plan.workspace)
            return 0
        } catch {
            let preferences = UserDefaults(suiteName: bundleID)
            preferences?.set(error.localizedDescription, forKey: "updateInstallError")
            preferences?.removeObject(forKey: "resumeAfterUpdate")
            preferences?.synchronize()
            // Kept next to the downloaded package for diagnosis; never touches user preferences.
            try? error.localizedDescription.write(to: planURL.deletingLastPathComponent().appendingPathComponent("install-error.txt"), atomically: true, encoding: .utf8)
            if let data = try? Data(contentsOf: planURL), let plan = try? JSONDecoder().decode(UpdateInstallPlan.self, from: data) {
                _ = try? run("/usr/bin/open", ["-n", plan.target.path])
            }
            return 1
        }
    }
}
