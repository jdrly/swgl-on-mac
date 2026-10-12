// Renders the app icon: the SWGL launcher logo on a deep-space squircle.
// Usage: swift make-icon.swift <logo.png> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: make-icon.swift <logo.png> <out.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px)
    // Apple's icon grid: 824/1024 body, 185.4/1024 corner radius.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 185.4 / 1024, yRadius: s * 185.4 / 1024)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.17, blue: 0.30, alpha: 1),
                        NSColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1)])!
        .draw(in: path, relativeCenterPosition: NSPoint(x: 0, y: 0.35))
    path.addClip()
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<90 {
        let r = CGFloat.random(in: 0.4...1.6, using: &rng) * s / 512
        let p = NSPoint(x: body.minX + CGFloat.random(in: 0...1, using: &rng) * body.width,
                        y: body.minY + CGFloat.random(in: 0...1, using: &rng) * body.height)
        NSColor(white: 1, alpha: CGFloat.random(in: 0.25...0.8, using: &rng)).setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).fill()
    }
    let w = body.width * 0.82
    let h = w * logo.size.height / logo.size.width
    logo.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
