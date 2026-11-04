import EQCore
import SwiftUI

struct SpatialPage: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.theme) private var theme

    var body: some View {
        let s = $model.settings.features.surround
        let v = model.settings.features.surround
        TwoColumns {
            Section2(title: "Virtual speakers", icon: "person.wave.2") {
                ParamSlider(title: "Speaker angle", value: s.speakerAngle, range: 10...60, step: 1, reset: 30) { "±\(Int($0))°" }
                ParamSlider(title: "Crossfeed", value: s.amount, range: 0...1, step: 0.01, reset: 0.6) { "\(Int($0 * 100))%" }
                ParamSlider(title: "Room", value: s.room, range: 0...1, step: 0.01, reset: 0.15) { $0 < 0.005 ? "Dry" : "\(Int($0 * 100))%" }
                ParamSlider(title: "Head shadow", value: s.headShadowHz, range: 600...5000, step: 50, reset: 1800) { "\(Int($0)) Hz" }
                Text(String(format: "Interaural delay %.2f ms", v.itdSeconds * 1000))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Section2(title: "Presets", icon: "square.grid.2x2") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(SurroundSettings.presets, id: \.name) { p in
                        Button(p.name) {
                            var x = model.settings.features.surround
                            x.speakerAngle = p.angle; x.amount = p.amount; x.room = p.room
                            model.settings.features.surround = x
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        } right: {
            Section2(title: "Stage", icon: "hifispeaker.2") {
                StageDiagram(angle: v.speakerAngle, room: v.room).frame(height: 220)
                Text("Each ear hears its own speaker directly and the opposite one slightly later and duller, as with real speakers. This moves the sound out of your head and onto a stage in front of you.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Tip: turn off Output ▸ Crossfeed when using virtual surround. It already includes crossfeed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StageDiagram: View {
    let angle: Double, room: Double
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { ctx, size in
            let head = CGPoint(x: size.width / 2, y: size.height * 0.78)
            let radius = min(size.width, size.height) * 0.62
            if room > 0.01 {
                ctx.stroke(Path(roundedRect: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16), cornerRadius: 12),
                           with: .color(theme.accent.opacity(0.15 + room * 0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            for side in [-1.0, 1.0] {
                let a = (side * angle - 90) * .pi / 180
                let p = CGPoint(x: head.x + cos(a) * radius, y: head.y + sin(a) * radius)
                var line = Path(); line.move(to: p); line.addLine(to: head)
                ctx.stroke(line, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                let box = CGRect(x: p.x - 14, y: p.y - 18, width: 28, height: 36)
                ctx.fill(Path(roundedRect: box, cornerRadius: 5), with: .color(theme.accent))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 2, width: 14, height: 14)), with: .color(.white.opacity(0.85)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 16, y: head.y - 16, width: 32, height: 32)), with: .color(.secondary.opacity(0.6)))
            ctx.draw(Text("You").font(.caption2), at: CGPoint(x: head.x, y: head.y + 28))
        }
    }
}
