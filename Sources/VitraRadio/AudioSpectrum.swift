import Foundation

// Eight fixed octave bands. State is private to the audio thread and preallocated.
final class AudioSpectrumDSP {
    static let centers: [Double] = [63, 125, 250, 500, 1000, 2000, 4000, 8000]
    private var b0 = [Double](repeating: 0, count: 8)
    private var a1 = [Double](repeating: 0, count: 8)
    private var a2 = [Double](repeating: 0, count: 8)
    private var z1 = [Double](repeating: 0, count: 16)
    private var z2 = [Double](repeating: 0, count: 16)
    private var sum = [Double](repeating: 0, count: 16)
    private var envelope = [Double](repeating: 0, count: 16)
    private var counts = [Int](repeating: 0, count: 2)
    func prepare(sampleRate: Double) {
        for band in 0..<8 {
            let omega = 2 * Double.pi * min(Self.centers[band], sampleRate * 0.45) / sampleRate
            let alpha = sin(omega) / (2 * 1.4)
            b0[band] = alpha / (1 + alpha)
            a1[band] = -2 * cos(omega) / (1 + alpha)
            a2[band] = (1 - alpha) / (1 + alpha)
        }
        for index in 0..<16 { z1[index] = 0; z2[index] = 0; sum[index] = 0; envelope[index] = 0 }
        counts[0] = 0; counts[1] = 0
    }
    func process(_ sample: Double, channel: Int) {
        guard channel < 2 else { return }
        counts[channel] += 1
        for band in 0..<8 {
            let index = channel * 8 + band
            let output = b0[band] * sample + z1[index]
            z1[index] = -a1[band] * output + z2[index]
            z2[index] = -b0[band] * sample - a2[band] * output
            sum[index] += output * output
        }
    }
    func publish(to meter: AudioMeterLevels, seconds: Double) {
        let attack = 1 - exp(-seconds / 0.025)
        let release = 1 - exp(-seconds / 0.16)
        for index in 0..<16 {
            let channel = index / 8
            let measured = counts[channel] > 0 ? sqrt(sum[index] / Double(counts[channel])) : 0
            envelope[index] += (measured > envelope[index] ? attack : release) * (measured - envelope[index])
            sum[index] = 0
        }
        for band in 0..<8 {
            meter.publishBand(band, left: envelope[band], right: counts[1] > 0 ? envelope[8 + band] : envelope[band])
        }
        counts[0] = 0; counts[1] = 0
    }
}
