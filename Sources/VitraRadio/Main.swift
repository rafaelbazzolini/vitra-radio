import AppKit
import Foundation

@main
struct VitraRadioMain {
    @MainActor
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--install-update"), CommandLine.arguments.count > index + 1 {
            exit(UpdateInstaller.runHelper(planURL: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-update-package"), CommandLine.arguments.count > index + 3 {
            exit(UpdateTests.verifyPackage(archive: URL(fileURLWithPath: CommandLine.arguments[index + 1]), checksums: URL(fileURLWithPath: CommandLine.arguments[index + 2]), version: CommandLine.arguments[index + 3]))
        }
        if CommandLine.arguments.contains("--self-test") {
            SelfTests.run()
            return
        }
        if CommandLine.arguments.contains("--verify-country-catalog") || CommandLine.arguments.contains("--verify-mini-vu") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            if CommandLine.arguments.contains("--verify-mini-vu") { MiniVUVerification.start() }
            else { CountryCatalogTests.start() }
            application.run()
            return
        }
        if CommandLine.arguments.contains("--verify-playback") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            PlaybackVerification.start()
            application.run()
            return
        }
        if CommandLine.arguments.contains("--verify-streams") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            StreamVerification.start()
            application.run()
            return
        }
        if CommandLine.arguments.contains("--verify-catalog") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            CatalogVerification.start()
            application.run()
            return
        }
        if CommandLine.arguments.contains("--verify-player-meter") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            AudioBalanceVerification.verifyPlayerMeter()
            application.run()
            return
        }
        if CommandLine.arguments.contains("--verify-audio-balance") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            AudioBalanceVerification.start()
            application.run()
            return
        }
        if CommandLine.arguments.contains("--verify-music-servers") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            MusicServerVerification.start()
            application.run()
            return
        }
        let preview = CommandLine.arguments.contains("--render-previews") || CommandLine.arguments.contains("--verify-mini") || CommandLine.arguments.contains("--verify-theme-menu") || CommandLine.arguments.contains("--verify-titlebar")
        let preferences = preview ? UserDefaults(suiteName: "com.vitra.radio.preview")! : .standard
        if preview { preferences.removePersistentDomain(forName: "com.vitra.radio.preview") }
        let application = NSApplication.shared
        let delegate = AppController(preferences: preferences, preview: preview)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
