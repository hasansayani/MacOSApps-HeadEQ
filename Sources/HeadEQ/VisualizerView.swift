import EQCore
import SwiftUI

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case bars, spectrum, wave, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bars: return "Bars"
        case .spectrum: return "Spectrum"
        case .wave: return "Wave"
        case .off: return "Off"
        }
    }
}

/// Pulls samples from the backend's ring and runs the analyzer once per frame.
final class VisualizerEngine {
    let analyzer = SpectrumAnalyzer(fftSize: 2048, bandCount: 56)
    private var buffer = [Float](repeating: 0, count: 2048)
    private(set) var wave = [Float](repeating: 0, count: 512)
    private var lastDate = Date()
    private var lastWritten = 0

    func tick(backend: AudioBackend, date: Date) {
        let dt = min(0.1, max(0.001, date.timeIntervalSince(lastDate)))
        lastDate = date
        let ring = backend.visualizerRing
        let written = ring.totalWritten
        if written != lastWritten {
            lastWritten = written
            buffer.withUnsafeMutableBufferPointer { ring.copyLatest(into: $0) }
            buffer.withUnsafeBufferPointer { analyzer.process($0, sampleRate: backend.sampleRate, dt: dt) }
            wave = Array(buffer.suffix(wave.count))
        } else {
            analyzer.decay(dt: dt)
            for i in wave.indices { wave[i] *= 0.8 }
        }
    }
}

struct VisualizerView: View {
    let style: VisualizerStyle
    let backend: AudioBackend
    @Environment(\.theme) private var theme
    @State private var engine = VisualizerEngine()

    var body: some View {
        if style == .off {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                Canvas { ctx, size in
                    engine.tick(backend: backend, date: timeline.date)
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: theme.gradient),
                        startPoint: CGPoint(x: 0, y: size.height),
                        endPoint: theme.palette.retro ? CGPoint(x: 0, y: 0) : CGPoint(x: size.width, y: 0))
                    switch style {
                    case .bars: drawBars(ctx, size, shading)
                    case .spectrum: drawSpectrum(ctx, size, shading)
                    case .wave: drawWave(ctx, size, shading)
                    case .off: break
                    }
                }
            }
        }
    }

    private func drawBars(_ ctx: GraphicsContext, _ size: CGSize, _ shading: GraphicsContext.Shading) {
        let levels = engine.analyzer.levels, peaks = engine.analyzer.peaks
        let n = CGFloat(levels.count)
        let slot = size.width / n, w = max(1, slot * 0.72)
        var bars = Path(), caps = Path()
        let retro = theme.palette.retro
        let segment: CGFloat = 4, segmentGap: CGFloat = 1.5
        for i in levels.indices {
            let x = CGFloat(i) * slot + (slot - w) / 2
            let h = CGFloat(levels[i]) * size.height
            if retro {
                // LED ladder, like classic player spectrum analysers.
                var top = size.height
                while top - segment >= size.height - h {
                    bars.addRect(CGRect(x: x, y: top - segment, width: w, height: segment))
                    top -= segment + segmentGap
                }
            } else {
                bars.addRoundedRect(in: CGRect(x: x, y: size.height - h, width: w, height: h),
                                    cornerSize: CGSize(width: w / 3, height: w / 3))
            }
            let py = size.height - CGFloat(peaks[i]) * size.height
            caps.addRect(CGRect(x: x, y: py - 2, width: w, height: 2))
        }
        var faded = ctx
        faded.opacity = 0.85
        faded.fill(bars, with: shading)
        ctx.fill(caps, with: .color(theme.accent.opacity(0.9)))
    }

    private func drawSpectrum(_ ctx: GraphicsContext, _ size: CGSize, _ shading: GraphicsContext.Shading) {
        let levels = engine.analyzer.levels
        guard levels.count > 1 else { return }
        var line = Path()
        let step = size.width / CGFloat(levels.count - 1)
        line.move(to: CGPoint(x: 0, y: size.height - CGFloat(levels[0]) * size.height))
        for i in 1..<levels.count {
            let p0 = CGPoint(x: CGFloat(i - 1) * step, y: size.height - CGFloat(levels[i - 1]) * size.height)
            let p1 = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(levels[i]) * size.height)
            line.addQuadCurve(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2), control: p0)
            if i == levels.count - 1 { line.addLine(to: p1) }
        }
        var fill = line
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()
        var faded = ctx
        faded.opacity = 0.35
        faded.fill(fill, with: shading)
        ctx.stroke(line, with: shading, lineWidth: 2)
    }

    private func drawWave(_ ctx: GraphicsContext, _ size: CGSize, _ shading: GraphicsContext.Shading) {
        let wave = engine.wave
        guard wave.count > 1 else { return }
        var line = Path()
        let mid = size.height / 2
        for (i, s) in wave.enumerated() {
            let p = CGPoint(x: CGFloat(i) / CGFloat(wave.count - 1) * size.width,
                            y: mid - CGFloat(max(-1, min(1, s * 1.5))) * mid * 0.9)
            i == 0 ? line.move(to: p) : line.addLine(to: p)
        }
        var glow = ctx
        glow.addFilter(.blur(radius: 4))
        glow.stroke(line, with: shading, lineWidth: 4)
        ctx.stroke(line, with: shading, lineWidth: 1.5)
    }
}
