import AVFoundation
import MediaToolbox
import Darwin

// Runs exclusively on the audio processing thread. No UI, locks, I/O or allocations in process().
final class AudioBalanceDSP {
    static let ceiling = 0.94
    private(set) var gain = 1.0
    private var meanSquare = 0.0
    private var limiter = 1.0
    private var hasSignal = false
    func reset() { gain = 1; meanSquare = 0; limiter = 1; hasSignal = false }
    func gains(sumSquares: Double, sampleCount: Int, peak: Double, seconds: Double) -> (Double, Double) {
        var before = gain
        guard sampleCount > 0, seconds > 0 else { return (gain * limiter, gain * limiter) }
        let square = sumSquares / Double(sampleCount)
        if square > 0.000001 { // Gate silence/noise; never chase a quiet pause.
            let integration = 1 - exp(-seconds / 2.0)
            meanSquare = meanSquare == 0 ? square : meanSquare + integration * (square - meanSquare)
            let desired = min(3.0, max(0.15, 0.12 / sqrt(meanSquare)))
            if !hasSignal {
                // Normalize the first audible block immediately, fading from zero to avoid a switching spike.
                hasSignal = true; before = 0; gain = desired
            } else {
                let smoothing = 1 - exp(-seconds / (desired < gain ? 0.25 : 4.0))
                gain += smoothing * (desired - gain)
            }
        }
        let peakGain = peak > 0 ? Self.ceiling / peak : Double.greatestFiniteMagnitude
        let neededLimiter = min(1, peakGain / max(before, gain))
        limiter = neededLimiter < limiter ? neededLimiter : limiter + (1 - exp(-seconds / 0.18)) * (neededLimiter - limiter)
        return (min(before * limiter, peakGain), min(gain * limiter, peakGain))
    }
}

private final class BalanceTapState {
    let dsp = AudioBalanceDSP()
    let spectrum = AudioSpectrumDSP()
    let meter: AudioMeterLevels?
    let normalize: Bool
    init(meter: AudioMeterLevels? = nil, normalize: Bool = true) { self.meter = meter; self.normalize = normalize }
    var format = AudioStreamBasicDescription()
    var validFormat = false
    var processedFrames = 0 // Access only when the tap is no longer processing (offline verification).
    func prepare(_ format: AudioStreamBasicDescription) {
        self.format = format
        let float = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let signed = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        validFormat = format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 && ((float && [32,64].contains(format.mBitsPerChannel)) || (signed && [16,32].contains(format.mBitsPerChannel)))
        dsp.reset()
        spectrum.prepare(sampleRate: format.mSampleRate)
    }
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard validFormat, frames > 0, format.mSampleRate > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let stride = Int(format.mBitsPerChannel / 8)
        let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        var sum = 0.0, peak = 0.0, count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = min(Int(buffer.mDataByteSize) / stride, frames * Int(buffer.mNumberChannels))
            for index in 0..<samples {
                let sample = read(data, index, floating: floating)
                let finite = sample.isFinite ? sample : 0
                sum += finite * finite; peak = max(peak, abs(finite)); count += 1
            }
        }
        let (start, end) = normalize ? dsp.gains(sumSquares: sum, sampleCount: count, peak: peak, seconds: Double(frames) / format.mSampleRate) : (1.0, 1.0)
        var leftSquare = 0.0, rightSquare = 0.0, leftCount = 0, rightCount = 0, channelOffset = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            let samples = min(Int(buffer.mDataByteSize) / stride, frames * channels)
            for index in 0..<samples {
                let input = read(data, index, floating: floating)
                let progress = Double(index / channels + 1) / Double(frames)
                let sample = input.isFinite ? (normalize ? min(AudioBalanceDSP.ceiling, max(-AudioBalanceDSP.ceiling, input * (start + (end - start) * progress))) : input) : 0
                let channel = channelOffset + index % channels
                if meter != nil { spectrum.process(sample, channel: channel) }
                if channel == 0 { leftSquare += sample * sample; leftCount += 1 }
                else if channel == 1 { rightSquare += sample * sample; rightCount += 1 }
                if floating && stride == 4 { data.assumingMemoryBound(to: Float.self)[index] = Float(sample) }
                else if floating { data.assumingMemoryBound(to: Double.self)[index] = sample }
                else if stride == 2 { data.assumingMemoryBound(to: Int16.self)[index] = Int16((sample * 32767).rounded()) }
                else { data.assumingMemoryBound(to: Int32.self)[index] = Int32((sample * 2147483647).rounded()) }
            }
            channelOffset += channels
        }
        if let meter { spectrum.publish(to: meter, seconds: Double(frames) / format.mSampleRate) }
        meter?.publish(left: leftCount > 0 ? sqrt(leftSquare / Double(leftCount)) : 0,
                       right: rightCount > 0 ? sqrt(rightSquare / Double(rightCount)) : (leftCount > 0 ? sqrt(leftSquare / Double(leftCount)) : 0))
        processedFrames += frames
    }
    private func read(_ data: UnsafeMutableRawPointer, _ index: Int, floating: Bool) -> Double {
        if floating { return format.mBitsPerChannel == 32 ? Double(data.assumingMemoryBound(to: Float.self)[index]) : data.assumingMemoryBound(to: Double.self)[index] }
        return format.mBitsPerChannel == 16 ? Double(data.assumingMemoryBound(to: Int16.self)[index]) / 32768 : Double(data.assumingMemoryBound(to: Int32.self)[index]) / 2147483648
    }
}

enum AudioBalanceTap {
    static func makeMix(trackID: CMPersistentTrackID? = nil, meter: AudioMeterLevels? = nil, normalize: Bool = true) -> AVAudioMix? {
        let state = Unmanaged.passRetained(BalanceTapState(meter: meter, normalize: normalize))
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: state.toOpaque(), init: { _, info, storage in
            storage.pointee = info
        }, finalize: { tap in
            Unmanaged<BalanceTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        }, prepare: { tap, _, format in
            Unmanaged<BalanceTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee)
        }, unprepare: nil, process: { tap, frames, _, buffers, framesOut, flagsOut in
            let result = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
            guard result == noErr else { framesOut.pointee = 0; return }
            Unmanaged<BalanceTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().process(buffers, frames: framesOut.pointee)
        })
        var tap: MTAudioProcessingTap?
        let status: OSStatus
        if #available(macOS 27.0, *) {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
            // Resolve at runtime so release builds also compile with the macOS 26 SDK.
            typealias CreateTap = @convention(c) (CFAllocator?, UnsafePointer<MTAudioProcessingTapCallbacks>, MTAudioProcessingTapCreationFlags, CMAudioFormatDescription?, UnsafeMutablePointer<MTAudioProcessingTap?>) -> OSStatus
            guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "MTAudioProcessingTapCreateWithPreferredFormat") else { state.release(); return nil }
            let create = unsafeBitCast(symbol, to: CreateTap.self)
            status = create(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, format.formatDescription, &tap)
        } else {
            guard trackID != nil else { state.release(); return nil }
            status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        }
        guard status == noErr, let tap else { state.release(); return nil }
        let parameters = AVMutableAudioMixInputParameters()
        parameters.trackID = trackID ?? 0
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
}
