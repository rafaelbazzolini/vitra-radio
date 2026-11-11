import AppKit
import Foundation

@main
struct VitraRadioMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTests.run()
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
