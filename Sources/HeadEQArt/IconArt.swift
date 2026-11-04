import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// HeadEQ artwork drawn in code: a rounded-square app icon (headband arc over
/// five EQ bars on a gradient) and a matching monochrome menu-bar glyph.
public enum IconArt {
    public struct RGB { public var r, g, b: CGFloat
        public init(hex: String) {
            let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255
        }
        var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    }

    static let barHeights: [CGFloat] = [0.38, 0.62, 0.86, 0.56, 0.42]

    /// Full-colour app icon. `gradient` runs top-left → bottom-right.
    public static func appIcon(size: Int, gradient: [String]) -> CGImage? {
        let s = CGFloat(size)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // macOS icon grid: artwork inset ~10% with a continuous-corner square.
        let inset = s * 0.1, rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)

        // Drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(squircle); ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()

        // Gradient body
        ctx.saveGState()
        ctx.addPath(squircle); ctx.clip()
        let colors = (gradient.isEmpty ? ["#64D2FF", "#0A84FF", "#5E5CE6"] : gradient).map { RGB(hex: $0).cg } as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil)!
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        // Soft top highlight
        let hl = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                            colors: [CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)] as CFArray, locations: nil)!
        ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
        ctx.restoreGState()

        drawGlyph(ctx, in: rect.insetBy(dx: rect.width * 0.17, dy: rect.width * 0.17), color: CGColor(gray: 1, alpha: 0.96),
                  shadow: true)
        return ctx.makeImage()
    }

    /// Monochrome glyph (black on transparent) for a template menu-bar image.
    public static func menuGlyph(size: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(size)
        drawGlyph(ctx, in: CGRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92),
                  color: CGColor(gray: 0, alpha: 1), shadow: false)
        return ctx.makeImage()
    }

    /// Headband arc with ear cups, and five EQ bars between them.
    static func drawGlyph(_ ctx: CGContext, in r: CGRect, color: CGColor, shadow: Bool) {
        ctx.saveGState()
        if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -r.width * 0.02), blur: r.width * 0.04, color: CGColor(gray: 0, alpha: 0.25)) }
        ctx.setFillColor(color); ctx.setStrokeColor(color)

        // Headband
        let band = r.width * 0.085
        ctx.setLineWidth(band); ctx.setLineCap(.round)
        let center = CGPoint(x: r.midX, y: r.minY + r.height * 0.42)
        let radius = r.width * 0.44
        ctx.addArc(center: center, radius: radius, startAngle: .pi * 0.97, endAngle: .pi * 0.03, clockwise: true)
        ctx.strokePath()

        // Ear cups
        let cupW = r.width * 0.15, cupH = r.height * 0.34
        for x in [center.x - radius - cupW / 2 + band * 0.2, center.x + radius - cupW / 2 - band * 0.2] {
            let cup = CGRect(x: x, y: r.minY + r.height * 0.1, width: cupW, height: cupH)
            ctx.addPath(CGPath(roundedRect: cup, cornerWidth: cupW * 0.45, cornerHeight: cupW * 0.45, transform: nil))
            ctx.fillPath()
        }

        // EQ bars
        let span = r.width * 0.46, barW = span / 8.2, gap = (span - barW * 5) / 4
        var x = r.midX - span / 2
        for h in barHeights {
            let bh = r.height * 0.52 * h
            let bar = CGRect(x: x, y: r.minY + r.height * 0.1, width: barW, height: bh)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
            ctx.fillPath()
            x += barW + gap
        }
        ctx.restoreGState()
    }

    public static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
