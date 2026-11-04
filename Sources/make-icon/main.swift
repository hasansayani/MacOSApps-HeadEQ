import Foundation
import HeadEQArt

// Usage: make-icon <output.iconset> [gradient hex colours…]
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: make-icon <dir.iconset> [#hex …]"); exit(1) }
let dir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let gradient = Array(args.dropFirst(2))
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        guard let img = IconArt.appIcon(size: px, gradient: gradient),
              IconArt.writePNG(img, to: dir.appendingPathComponent(name)) else { print("failed \(name)"); exit(1) }
    }
}
print("wrote \(dir.path)")
