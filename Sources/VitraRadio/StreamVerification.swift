import Foundation
import AVFoundation
import CoreMedia

enum StreamVerification {
    @MainActor static func start() {
        Task { @MainActor in
            var failures = 0
            for station in Station.all {
                print("STREAM: \(station.name)")
                fflush(stdout)
                let asset = AVURLAsset(url: station.stream, options: [AVURLAssetHTTPUserAgentKey: "VitraRadio/1.0"])
                let player = AVPlayer()
                let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
                do {
                    guard try await asset.load(.isPlayable) else { throw VerificationError.notPlayable }
                    // Em HLS ao vivo, AVAsset.tracks pode permanecer vazio. As
                    // faixas e buffers efetivos são publicados pelo player item.
                    player.replaceCurrentItem(with: item)
                    let deadline = Date().addingTimeInterval(25)
                    while Date() < deadline && (item.status != .readyToPlay || item.loadedTimeRanges.isEmpty) {
                        if item.status == .failed { throw item.error ?? VerificationError.notPlayable }
                        try await Task.sleep(nanoseconds: 200_000_000)
                    }
                    guard item.status == .readyToPlay, !item.tracks.isEmpty, !item.loadedTimeRanges.isEmpty else { throw VerificationError.noAudio }
                    print("PASS: \(station.name) · AVFoundation preparou \(item.tracks.count) faixa(s) e recebeu buffer de mídia, sem abrir saída de som")
                } catch {
                    failures += 1
                    print("FAIL: \(station.name) · \(error)")
                }
                player.replaceCurrentItem(with: nil)
                asset.cancelLoading()
                fflush(stdout)
            }
            print("STREAM_VERIFICATION_\(failures == 0 ? "OK" : "FAILED"): \(failures) falhas")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }
    enum VerificationError: Error { case notPlayable, noAudio }
}
