// Renders the app icon into an .iconset directory. Run: swift tools/MakeIcon.swift <out.iconset>
//
// The mark is the app in miniature: a sheet of paper, the ruled margin in aged
// sepia, and a check struck across it in fresh iron-gall navy. The rule is
// dropped below 64px, where it would only muddy the check.
import AppKit

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green:   CGFloat((value >> 8) & 0xFF) / 255,
            blue:    CGFloat(value & 0xFF) / 255,
            alpha: alpha)
}

func render(size: CGFloat) -> Data? {
    let px = Int(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // The sheet, inset to leave the standard macOS icon margin.
    let inset = size * 0.085
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let sheet = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGradient(starting: hex(0xFFFFFF), ending: hex(0xEFEEE8))?.draw(in: sheet, angle: -90)

    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    // Feint ruling. Only at sizes where it reads as paper rather than noise.
    if size >= 128 {
        hex(0xCDD8E4).setStroke()
        for y in [0.285, 0.445, 0.605, 0.765] as [CGFloat] {
            let line = NSBezierPath()
            line.move(to: p(0.09, y))
            line.line(to: p(0.91, y))
            line.lineWidth = max(rect.width * 0.013, 0.75)
            line.stroke()
        }
    }

    // The margin, in aged ink. Dropped below 64px, where it only muddies the check.
    if size >= 64 {
        let margin = NSBezierPath()
        margin.move(to: p(0.255, 0.075))
        margin.line(to: p(0.255, 0.925))
        margin.lineWidth = max(rect.width * 0.024, 1)
        margin.lineCapStyle = .round
        hex(0x6E3E29).setStroke()
        margin.stroke()
    }

    // The check, in fresh ink — written in the margin's writing area, as it
    // would be on the page itself. Below 64px the margin is gone, so the check
    // recentres rather than sitting off to one side for no visible reason.
    let shift: CGFloat = size >= 64 ? 0 : -0.073
    let check = NSBezierPath()
    check.move(to: p(0.350 + shift, 0.480))
    check.line(to: p(0.487 + shift, 0.338))
    check.line(to: p(0.800 + shift, 0.672))
    check.lineWidth = rect.width * 0.112
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    hex(0x1D3557).setStroke()
    check.stroke()

    // A hairline so the sheet still reads as an edge on a light background.
    let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                            xRadius: radius, yRadius: radius)
    edge.lineWidth = max(size * 0.005, 0.75)
    hex(0xD2D0C7).setStroke()
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: MakeIcon.swift <out.iconset>\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let variants: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (size, name) in variants {
    guard let data = render(size: size) else { continue }
    try data.write(to: out.appendingPathComponent(name))
}
print("icons written to \(out.path)")
