import SwiftUI
import Darwin

// One audio-thread writer, UI readers; atomics avoid locks and allocations in the tap.
final class AudioMeterLevels {
    private let packed = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    private let bands = UnsafeMutablePointer<Int64>.allocate(capacity: 8)
    private let stamp = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    private let secondsPerTick: Double
    init() {
        bands.initialize(repeating: 0, count: 8)
        packed.initialize(to: 0); stamp.initialize(to: 0)
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        secondsPerTick = Double(info.numer) / Double(info.denom) / 1_000_000_000
    }
    deinit { bands.deinitialize(count: 8); bands.deallocate(); packed.deinitialize(count: 1); packed.deallocate(); stamp.deinitialize(count: 1); stamp.deallocate() }
    private func store(_ value: Int64, at pointer: UnsafeMutablePointer<Int64>) {
        var old = OSAtomicAdd64Barrier(0, pointer)
        while !OSAtomicCompareAndSwap64Barrier(old, value, pointer) { old = OSAtomicAdd64Barrier(0, pointer) }
    }
    func publish(left: Double, right: Double) {
        let bits = UInt64(Float(left).bitPattern) | (UInt64(Float(right).bitPattern) << 32)
        store(Int64(bitPattern: bits), at: packed)
        store(Int64(bitPattern: mach_absolute_time()), at: stamp)
    }
    func publishBand(_ index: Int, left: Double, right: Double) {
        let bits = UInt64(Float(left).bitPattern) | (UInt64(Float(right).bitPattern) << 32)
        store(Int64(bitPattern: bits), at: bands.advanced(by: index))
    }
    func spectrum(right: Bool) -> [Double] {
        let timestamp = UInt64(bitPattern: OSAtomicAdd64Barrier(0, stamp))
        guard timestamp > 0, Double(mach_absolute_time() - timestamp) * secondsPerTick < 0.3 else { return Array(repeating: 0, count: 8) }
        return (0..<8).map { index in
            let bits = UInt64(bitPattern: OSAtomicAdd64Barrier(0, bands.advanced(by: index)))
            return Double(Float(bitPattern: UInt32(truncatingIfNeeded: right ? bits >> 32 : bits)))
        }
    }
    func read() -> (Double, Double) {
        let timestamp = UInt64(bitPattern: OSAtomicAdd64Barrier(0, stamp))
        guard timestamp > 0, Double(mach_absolute_time() - timestamp) * secondsPerTick < 0.3 else { return (0, 0) }
        let bits = UInt64(bitPattern: OSAtomicAdd64Barrier(0, packed))
        return (Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits))), Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits >> 32))))
    }
}

enum VUStyle: String, CaseIterable {
    case off = "Desligado", digital = "VU Digital", modern = "VU Moderno", analog = "VU Analógico"
}

struct VUStyleMenu: View {
    @EnvironmentObject private var app: AppController
    @Environment(\.appPalette) private var palette
    var body: some View {
        Menu {
            ForEach(VUStyle.allCases, id: \.self) { style in
                Button { app.vuStyle = style } label: {
                    if app.vuStyle == style { Label(style.rawValue, systemImage: "checkmark") }
                    else { Text(style.rawValue) }
                }
            }
        } label: {
            Label(app.vuStyle == .off ? "VU" : app.vuStyle.rawValue, systemImage: "chart.bar.xaxis")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.accent)
        }.menuStyle(.borderlessButton).fixedSize().help("Medidores de áudio em tempo real")
    }
}

struct LiveVUMeter: View {
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.appPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let style: VUStyle
    let right: Bool
    private var width: CGFloat { style == .analog ? 118 : 68 }
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.12 : 1.0 / 30)) { _ in
            let levels = radio.audioLevels.read()
            let amplitude = radio.state.isPlaying && !radio.muted ? (right ? levels.1 : levels.0) * radio.volume : 0
            let db = amplitude > 0.00001 ? 20 * log10(amplitude) : -60
            let value = max(0, min(1, (db + 60) / 60))
            let bands = radio.audioLevels.spectrum(right: right)
            let enabled = radio.state.isPlaying && !radio.muted
            VStack(spacing: 12) {
                Text(right ? "RIGHT" : "LEFT").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.2)
                if style == .digital {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<8) { column in
                            let bandAmplitude = enabled ? bands[column] * radio.volume : 0
                            let bandDB = bandAmplitude > 0.00001 ? 20 * log10(bandAmplitude) : -70
                            let bandLevel = max(0, min(1, (bandDB + 70) / 60))
                            VStack(spacing: 3) {
                                ForEach((0..<24).reversed(), id: \.self) { row in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill((row > 21 ? Color.red : row > 18 ? Color.orange : palette.accent).opacity(bandLevel > Double(row) / 24 ? 0.95 : 0.08))
                                }
                            }
                        }
                    }.frame(height: 196)
                    .help("Oito bandas reais: 63, 125, 250, 500 Hz, 1, 2, 4 e 8 kHz")
                } else if style == .modern {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(palette.text.opacity(0.06))
                        Capsule().fill(LinearGradient(colors: [palette.accent.opacity(0.45), palette.accent, .orange, .red], startPoint: .bottom, endPoint: .top))
                            .frame(height: 196 * value)
                        ForEach(1..<6) { index in
                            Rectangle().fill(palette.background.opacity(0.75)).frame(height: 1).offset(y: -CGFloat(index) * 28)
                        }
                    }.frame(width: 22, height: 196)
                } else {
                    analog(value: value).frame(height: 138)
                    Text("VU").font(.system(size: 15, weight: .medium, design: .serif)).tracking(3)
                }
                Text(amplitude > 0.00001 ? String(format: "%.0f dB", db) : "−∞ dB")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }.foregroundStyle(palette.muted).padding(.vertical, 16).frame(width: width)
                .background(palette.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.line).allowsHitTesting(false))
                .accessibilityLabel("Nível do canal \(right ? "direito" : "esquerdo"): \(Int(db)) decibéis")
        }
    }
    private func analog(value: Double) -> some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height - 20)
            let radius = size.width * 0.42
            for tick in 0...10 {
                let angle = (-150.0 + Double(tick) * 12) * .pi / 180
                let outer = CGPoint(x: pivot.x + cos(angle) * radius, y: pivot.y + sin(angle) * radius)
                let inner = CGPoint(x: pivot.x + cos(angle) * (radius - 8), y: pivot.y + sin(angle) * (radius - 8))
                var path = Path(); path.move(to: inner); path.addLine(to: outer)
                context.stroke(path, with: .color(tick > 8 ? .red : palette.accent.opacity(0.7)), lineWidth: 1.5)
                if tick % 2 == 0 {
                    let label = CGPoint(x: pivot.x + cos(angle) * (radius + 11), y: pivot.y + sin(angle) * (radius + 11))
                    context.draw(Text("\(-20 + tick * 2)").font(.system(size: 7, design: .monospaced)).foregroundColor(palette.muted), at: label)
                }
            }
            let angle = (-150 + value * 120) * .pi / 180
            var needle = Path(); needle.move(to: pivot)
            needle.addLine(to: CGPoint(x: pivot.x + cos(angle) * (radius - 5), y: pivot.y + sin(angle) * (radius - 5)))
            context.stroke(needle, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: pivot.x - 4, y: pivot.y - 4, width: 8, height: 8)), with: .color(palette.accent))
        }
    }
}
