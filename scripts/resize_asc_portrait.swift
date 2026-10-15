import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: resize_asc_portrait.swift <input> <output>\n", stderr)
    exit(1)
}

let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let canvasW: CGFloat = 1242
let canvasH: CGFloat = 2688

guard let src = NSImage(contentsOfFile: inPath) else {
    fputs("failed to load \(inPath)\n", stderr)
    exit(1)
}

let srcW = src.size.width
let srcH = src.size.height

func makeRep(_ w: CGFloat, _ h: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(w),
        pixelsHigh: Int(h),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: w, height: h)
    return rep
}

let canvas = makeRep(canvasW, canvasH)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: canvas)!
ctx.imageInterpolation = .high
NSGraphicsContext.current = ctx

NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.047, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: canvasW, height: canvasH).fill()

let scale = min(canvasW / srcW, canvasH / srcH)
let drawW = srcW * scale
let drawH = srcH * scale
let drawX = (canvasW - drawW) / 2
let drawY = (canvasH - drawH) / 2

src.draw(
    in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
    from: .zero,
    operation: .copy,
    fraction: 1
)

NSGraphicsContext.restoreGraphicsState()

guard let png = canvas.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: outPath))
print("ok \(outPath) \(Int(canvasW))x\(Int(canvasH))")
