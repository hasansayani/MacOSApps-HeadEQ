/// Biquad filter design (RBJ Audio EQ Cookbook) and frequency-response math.

public enum FilterType: String, Codable, Sendable, CaseIterable {
    case peak, lowShelf, highShelf
}

/// A parametric EQ filter description, independent of sample rate.
public struct FilterSpec: Codable, Hashable, Sendable {
    public var type: FilterType
    public var frequency: Double   // Hz
    public var gain: Double        // dB
    public var q: Double

    public init(_ type: FilterType, _ frequency: Double, _ gain: Double, q: Double = 1.0) {
        self.type = type; self.frequency = frequency; self.gain = gain; self.q = q
    }

    public static func peak(_ f: Double, _ g: Double, q: Double = 1.0) -> FilterSpec { .init(.peak, f, g, q: q) }
    public static func lowShelf(_ f: Double, _ g: Double, q: Double = 0.707) -> FilterSpec { .init(.lowShelf, f, g, q: q) }
    public static func highShelf(_ f: Double, _ g: Double, q: Double = 0.707) -> FilterSpec { .init(.highShelf, f, g, q: q) }
}

/// Normalized biquad coefficients (a0 == 1).
public struct BiquadCoefficients: Hashable, Sendable {
    public var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    public static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    public init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    public init(_ spec: FilterSpec, sampleRate: Double) {
        let nyquist = sampleRate / 2
        let f = min(max(spec.frequency, 10), nyquist * 0.95)
        if abs(spec.gain) < 0.001 { self = .identity; return }

        let A = pow(10, spec.gain / 40)
        let w0 = 2 * Double.pi * f / sampleRate
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * max(spec.q, 0.05))
        var b0, b1, b2, a0, a1, a2: Double

        switch spec.type {
        case .peak:
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
        case .lowShelf:
            let s = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) - (A - 1) * cw + s)
            b1 = 2 * A * ((A - 1) - (A + 1) * cw)
            b2 = A * ((A + 1) - (A - 1) * cw - s)
            a0 = (A + 1) + (A - 1) * cw + s
            a1 = -2 * ((A - 1) + (A + 1) * cw)
            a2 = (A + 1) + (A - 1) * cw - s
        case .highShelf:
            let s = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) + (A - 1) * cw + s)
            b1 = -2 * A * ((A - 1) + (A + 1) * cw)
            b2 = A * ((A + 1) + (A - 1) * cw - s)
            a0 = (A + 1) - (A - 1) * cw + s
            a1 = 2 * ((A - 1) - (A + 1) * cw)
            a2 = (A + 1) - (A - 1) * cw - s
        }
        self.init(b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
                  a1: Float(a1 / a0), a2: Float(a2 / a0))
    }

    /// Magnitude response in dB at `frequency`.
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
        let nr = Double(b0) + Double(b1) * c1 + Double(b2) * c2
        let ni = -(Double(b1) * s1 + Double(b2) * s2)
        let dr = 1 + Double(a1) * c1 + Double(a2) * c2
        let di = -(Double(a1) * s1 + Double(a2) * s2)
        let mag2 = (nr * nr + ni * ni) / max(dr * dr + di * di, 1e-30)
        return 10 * log10(max(mag2, 1e-30))
    }
}

public enum FrequencyResponse {
    /// Log-spaced frequencies from 20 Hz to 20 kHz.
    public static func logFrequencies(count: Int = 200, from lo: Double = 20, to hi: Double = 20_000) -> [Double] {
        (0..<count).map { lo * pow(hi / lo, Double($0) / Double(count - 1)) }
    }

    /// Combined response (dB) of a filter chain plus preamp.
    public static func curve(filters: [FilterSpec], preamp: Double, sampleRate: Double = 48_000,
                             frequencies: [Double]) -> [Double] {
        let coeffs = filters.map { BiquadCoefficients($0, sampleRate: sampleRate) }
        return frequencies.map { f in coeffs.reduce(preamp) { $0 + $1.magnitudeDB(at: f, sampleRate: sampleRate) } }
    }

    /// Highest boost of the chain (dB). Used to compute a clip-safe preamp.
    public static func peakGain(filters: [FilterSpec], sampleRate: Double = 48_000) -> Double {
        curve(filters: filters, preamp: 0, sampleRate: sampleRate,
              frequencies: logFrequencies(count: 400)).max() ?? 0
    }
}
