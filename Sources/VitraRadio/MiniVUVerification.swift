import AppKit
import SwiftUI

enum MiniVUVerification {
    @MainActor static func start() {
        Task { @MainActor in
            var failures = 0
            func check(_ value: Bool, _ label: String) { print("\(value ? "PASS" : "FAIL"): \(label)"); if !value { failures += 1 } }
            let meter = AudioMeterLevels()
            let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 260, height: 70), styleMask: [.borderless], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: LiveMiniVU(meter: meter, style: .digital, enabled: true, volume: 0.8).background(Color.black))
            window.contentView = host
            window.orderFrontRegardless()
            func publish(_ amplitude: Double) {
                for band in 0..<8 { meter.publishBand(band, left: amplitude * Double(band + 1) / 8, right: amplitude * Double(8 - band) / 8) }
                meter.publish(left: amplitude, right: amplitude * 0.6)
            }
            func snapshot() -> Data? {
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                return bitmap.representation(using: .png, properties: [:])
            }
            for style in [VUStyle.digital, .analog] {
                host.rootView = LiveMiniVU(meter: meter, style: style, enabled: true, volume: 0.8).background(Color.black)
                publish(0.003)
                try? await Task.sleep(nanoseconds: 180_000_000)
                let low = snapshot()
                publish(0.35)
                try? await Task.sleep(nanoseconds: 180_000_000)
                let high = snapshot()
                check(low != nil && high != nil && low != high, "\(style.rawValue) redesenha com novas amostras sem recriar o player")
                try? await Task.sleep(nanoseconds: 400_000_000)
                let stale = snapshot()
                check(stale != nil && stale != high, "\(style.rawValue) volta ao silêncio quando as amostras deixam de chegar")
            }
            window.orderOut(nil)
            print("MINI_VU_DRAWING_\(failures == 0 ? "OK" : "FAILED"): \(failures) falhas (amostras controladas, sem som)")
            fflush(stdout); exit(failures == 0 ? 0 : 1)
        }
    }
}
