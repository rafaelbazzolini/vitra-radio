import AppKit

@MainActor
final class AnimatedAppIcon {
    private var timer: Timer?
    private var frame = 0
    private var frames: [NSImage] = []
    private var original: NSImage?

    func setPlaying(_ playing: Bool) {
        guard playing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { stop(); return }
        guard timer == nil else { return }
        original = NSApp.applicationIconImage
        if frames.isEmpty { frames = (0..<32).map { Self.image(phase: Double($0) * .pi / 16) } }
        tick()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { self?.stop(); return }
                self?.tick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        NSApp.applicationIconImage = frames[frame % frames.count]
        frame += 1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let original { NSApp.applicationIconImage = original }
        original = nil
        frame = 0
    }

    static func image(phase: Double) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: 0.25, y: 0.25)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
            NSColor(red: 0.07, green: 0.115, blue: 0.08, alpha: 1).setFill()
            let background = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)
            background.fill()
            background.addClip()
            for index in 0..<8 {
                let radius = CGFloat(150 + index * 61)
                NSColor(red: 0.765, green: 0.957, blue: 0.478, alpha: 0.15 - Double(index) * 0.012).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: 710 - radius, y: 310 - radius, width: radius * 2, height: radius * 2))
                ring.lineWidth = 3
                ring.stroke()
            }
            NSColor(red: 0.765, green: 0.957, blue: 0.478, alpha: 1).setFill()
            for index in 0..<5 {
                let wave = (sin(phase + Double(index) * 1.3) + 1) / 2
                let height = 150 + wave * (index == 2 ? 360 : 260)
                let bar = NSRect(x: 286 + Double(index) * 94, y: 512 - height / 2, width: 55, height: height)
                NSBezierPath(roundedRect: bar, xRadius: 27.5, yRadius: 27.5).fill()
            }
            NSColor(white: 1, alpha: 0.13).setStroke()
            let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 194, yRadius: 194)
            edge.lineWidth = 3
            edge.stroke()
            return true
        }
    }
}
