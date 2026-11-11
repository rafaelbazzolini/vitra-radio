import AppKit
import SwiftUI

enum MiniSizing {
    static let minimum = CGSize(width: 230, height: 44)
    static let maximum = CGSize(width: 620, height: 200)

    static func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: min(maximum.width, max(minimum.width, size.width.isFinite ? size.width : 244)),
               height: min(maximum.height, max(minimum.height, size.height.isFinite ? size.height : 64)))
    }

    @MainActor static func dockFrame(on screen: NSScreen) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerName as String] as? String == "Dock",
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            let frame = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            guard frame.intersects(screen.frame), frame.height >= 30, frame.height <= 220,
                  frame.width > frame.height * 2, frame.minY < screen.frame.minY + 90 else { return nil }
            return frame
        }.max(by: { $0.width < $1.width })
    }

    @MainActor static func dockHeight(on screen: NSScreen) -> CGFloat {
        if let frame = dockFrame(on: screen) { return clamped(CGSize(width: 244, height: frame.height)).height }
        let reserved = screen.visibleFrame.minY - screen.frame.minY
        if reserved > 25 { return max(44, min(180, reserved - 8)) }
        let tile = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 48
        return max(44, min(180, (tile > 0 ? tile : 48) + 16))
    }
}

struct MiniResizeHandle: NSViewRepresentable {
    let resize: (CGSize, CGFloat) -> Void

    final class HandleView: NSView {
        var resize: ((CGSize, CGFloat) -> Void)?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window, let resize else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let frame = window.frame
            // Keep tracking through layout changes when the compact/full layout switches.
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let current = window.convertPoint(toScreen: next.locationInWindow)
                resize(CGSize(width: frame.width + current.x - point.x,
                              height: frame.height + current.y - point.y), frame.minY)
            }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(white: 0.62, alpha: 0.65).setStroke()
            for offset in [3.0, 7.0] {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: bounds.maxX - offset - 3, y: bounds.maxY - 3))
                path.line(to: CGPoint(x: bounds.maxX - 3, y: bounds.maxY - offset - 3))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }
    func makeNSView(context: Context) -> HandleView { let view = HandleView(); view.resize = resize; return view }
    func updateNSView(_ nsView: HandleView, context: Context) { nsView.resize = resize }
}
