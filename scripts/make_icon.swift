import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// Squircle macOS (marge 100 px comme les gabarits Apple)
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
// Ombre portée
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); path.fill()
ctx.restoreGState()
path.addClip()
let grad = NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.30, blue: 1.0, alpha: 1),
                               NSColor(srgbRed: 0.62, green: 0.25, blue: 0.95, alpha: 1),
                               NSColor(srgbRed: 0.98, green: 0.36, blue: 0.62, alpha: 1)],
                      atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
grad.draw(in: rect, angle: -55)
// Reflet supérieur
let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
gloss.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height/2), angle: -90)

func card(_ r: CGRect, angle: CGFloat, alpha: CGFloat, lines: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: angle * .pi / 180); ctx.translateBy(x: -r.midX, y: -r.midY)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor(srgbRed: 0.15, green: 0.05, blue: 0.4, alpha: 0.45).cgColor)
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: r, xRadius: 46, yRadius: 46).fill()
    ctx.restoreGState()
    if lines {
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: angle * .pi / 180); ctx.translateBy(x: -r.midX, y: -r.midY)
        let widths: [CGFloat] = [0.70, 0.55, 0.62, 0.38]
        for (i, w) in widths.enumerated() {
            let y = r.maxY - 95 - CGFloat(i) * 62
            let lr = CGRect(x: r.minX + 52, y: y, width: (r.width - 104) * w, height: 26)
            let c = i == 0 ? NSColor(srgbRed: 0.50, green: 0.30, blue: 0.98, alpha: 1) : NSColor(srgbRed: 0.75, green: 0.72, blue: 0.86, alpha: 1)
            c.setFill(); NSBezierPath(roundedRect: lr, xRadius: 13, yRadius: 13).fill()
        }
        ctx.restoreGState()
    }
}
card(CGRect(x: 330, y: 330, width: 420, height: 470), angle: 9, alpha: 0.38, lines: false)
card(CGRect(x: 290, y: 250, width: 420, height: 470), angle: -4, alpha: 1.0, lines: true)
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
