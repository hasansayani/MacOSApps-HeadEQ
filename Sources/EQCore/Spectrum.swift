/// Visualizer support: a lock-free sample ring (audio thread → UI) and a
/// pure-Swift FFT spectrum analyzer. Portable across platforms.

/// Single-producer / single-consumer ring of the most recent output samples.
/// The reader may occasionally see a torn frame; that's fine for visuals.
public final class SampleRing {
    public let capacity: Int
    private let buffer: UnsafeMutablePointer<Float>
    private var writeIndex = 0

    public init(capacity: Int = 8192) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0, "capacity must be a power of two")
        self.capacity = capacity
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
    }
    deinit { buffer.deallocate() }

    /// Audio thread. Writes the mono mix of up to two channels. No allocation.
    public func writeMix(_ left: UnsafePointer<Float>, _ right: UnsafePointer<Float>?, frames: Int) {
        var w = writeIndex
        let mask = capacity - 1
        if let right {
            for t in 0..<frames { buffer[w & mask] = (left[t] + right[t]) * 0.5; w &+= 1 }
        } else {
            for t in 0..<frames { buffer[w & mask] = left[t]; w &+= 1 }
        }
        writeIndex = w
    }

    /// UI thread. Copies the newest `dst.count` samples (oldest first).
    public func copyLatest(into dst: UnsafeMutableBufferPointer<Float>) {
        let n = min(dst.count, capacity)
        let end = writeIndex
        let mask = capacity - 1
        for i in 0..<n { dst[i] = buffer[(end - n + i) & mask] }
    }

    public var totalWritten: Int { writeIndex }
}

public final class SpectrumAnalyzer {
    public let fftSize: Int
    public let bandCount: Int
    public private(set) var levels: [Float]      // 0…1, smoothed
    public private(set) var peaks: [Float]       // 0…1, peak-hold with fall-off

    private let log2n: Int
    private let window: [Float]
    private var re: [Float], im: [Float]
    private let cosTable: [Float], sinTable: [Float]
    private let bitReverse: [Int]
    private var bandEdges: [Int] = []
    private var configuredRate: Double = 0
    private let floorDB: Float = -72

    public init(fftSize: Int = 2048, bandCount: Int = 64) {
        precondition(fftSize & (fftSize - 1) == 0)
        self.fftSize = fftSize
        self.bandCount = bandCount
        log2n = Int(log2(Double(fftSize)))
        window = (0..<fftSize).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(fftSize - 1))) }
        re = .init(repeating: 0, count: fftSize)
        im = .init(repeating: 0, count: fftSize)
        cosTable = (0..<fftSize / 2).map { Float(cos(-2 * Double.pi * Double($0) / Double(fftSize))) }
        sinTable = (0..<fftSize / 2).map { Float(sin(-2 * Double.pi * Double($0) / Double(fftSize))) }
        var rev = [Int](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            var x = i, r = 0
            for _ in 0..<Int(log2(Double(fftSize))) { r = (r << 1) | (x & 1); x >>= 1 }
            rev[i] = r
        }
        bitReverse = rev
        levels = .init(repeating: 0, count: bandCount)
        peaks = .init(repeating: 0, count: bandCount)
    }

    private func configure(sampleRate: Double) {
        configuredRate = sampleRate
        let lo = 30.0, hi = min(18_000, sampleRate / 2 * 0.95)
        let binHz = sampleRate / Double(fftSize)
        bandEdges = (0...bandCount).map { i in
            let f = lo * pow(hi / lo, Double(i) / Double(bandCount))
            return max(1, min(fftSize / 2 - 1, Int((f / binHz).rounded())))
        }
    }

    /// Analyse the newest `fftSize` samples. `dt` = seconds since last call (for smoothing).
    public func process(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double, dt: Double) {
        if sampleRate != configuredRate { configure(sampleRate: sampleRate) }
        let n = min(samples.count, fftSize)
        for i in 0..<fftSize {
            let s: Float = i < n ? samples[samples.count - n + i] : 0
            re[bitReverse[i]] = s * window[i]
            im[bitReverse[i]] = 0
        }
        // Iterative radix-2 Cooley–Tukey.
        var size = 2
        while size <= fftSize {
            let half = size / 2, step = fftSize / size
            var start = 0
            while start < fftSize {
                for k in 0..<half {
                    let c = cosTable[k * step], s = sinTable[k * step]
                    let a = start + k, b = a + half
                    let tr = re[b] * c - im[b] * s
                    let ti = re[b] * s + im[b] * c
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
                start += size
            }
            size <<= 1
        }

        let norm: Float = 4 / Float(fftSize)          // Hann window + one-sided scaling
        let attack = Float(min(1, dt * 30)), release = Float(min(1, dt * 6))
        let peakFall = Float(dt * 0.6)
        for band in 0..<bandCount {
            let a = bandEdges[band], b = max(bandEdges[band + 1], a + 1)
            var m: Float = 0
            for bin in a..<b { m = max(m, (re[bin] * re[bin] + im[bin] * im[bin]).squareRoot()) }
            let db = 20 * log10(max(m * norm, 1e-9))
            let target = max(0, min(1, (db - floorDB) / -floorDB))
            let k = target > levels[band] ? attack : release
            levels[band] += (target - levels[band]) * k
            peaks[band] = max(levels[band], peaks[band] - peakFall)
        }
    }

    /// Let the display fall to zero when no audio is flowing.
    public func decay(dt: Double) {
        let f = Float(min(1, dt * 6))
        for i in 0..<bandCount {
            levels[i] -= levels[i] * f
            peaks[i] = max(levels[i], peaks[i] - Float(dt * 0.6))
        }
    }
}
