import AppKit
import Foundation

// App Store portrait layout — iPhone (1242×2688) and iPad (2064×2752).
struct ASCLayout {
    static let iPhone = ASCLayout(canvasW: 1242, canvasH: 2688, refW: 1290, refH: 2796)
    static let iPad = ASCLayout(canvasW: 2064, canvasH: 2752, refW: 1290, refH: 2796)

    let canvasW: CGFloat
    let canvasH: CGFloat
    let refW: CGFloat
    let refH: CGFloat

    // Phone bitmap size after 02 crop (510×1024 source, inset 8/52).
    let refPhoneW: CGFloat = 494
    let refPhoneH: CGFloat = 972

    func sx(_ v: CGFloat) -> CGFloat { v * canvasW / refW }
    func sy(_ v: CGFloat) -> CGFloat { v * canvasH / refH }

    var sidePad: CGFloat { sx(70) }
    var topAfterCopy: CGFloat { sy(410) }
    var bottomPad: CGFloat { sy(80) }

    var titleFont: NSFont { NSFont.systemFont(ofSize: sy(58), weight: .bold) }
    var subtitleFont: NSFont { NSFont.systemFont(ofSize: sy(42), weight: .medium) }
    var titleRect: NSRect {
        NSRect(x: sx(40), y: canvasH - sy(230), width: canvasW - sx(96), height: sy(110))
    }
    var subtitleRect: NSRect {
        NSRect(x: sx(48), y: canvasH - sy(360), width: canvasW - sx(96), height: sy(90))
    }

    var phoneDrawRect: NSRect {
        let availW = canvasW - sidePad * 2
        let availH = canvasH - topAfterCopy - bottomPad
        let scale = min(availW / refPhoneW, availH / refPhoneH)
        let drawW = refPhoneW * scale
        let drawH = refPhoneH * scale
        let drawX = (canvasW - drawW) / 2
        let drawY = bottomPad + (availH - drawH) / 2
        return NSRect(x: drawX, y: drawY, width: drawW, height: drawH)
    }

    /// Crop used for 02 (510×1024 phone-UI captures).
    static let phoneUICrop = (top: CGFloat(0), bottom: CGFloat(52), x: CGFloat(8))
    /// Crop used for 478×1024 simulator-window captures.
    static let simulatorCrop = (top: CGFloat(88), bottom: CGFloat(10), x: CGFloat(18))
    /// Crop phone mock from 1024×1536 AI marketing images (03).
    static let aiMockCrop03 = (top: CGFloat(250), bottom: CGFloat(16), x: CGFloat(70))
    /// Crop phone mock from 1024×1536 AI marketing images (04 — wider device art).
    static let aiMockCrop04 = (top: CGFloat(250), bottom: CGFloat(8), x: CGFloat(128))
}

enum PhoneContentMode {
    /// Real screenshots: aspect-fill normalize to 02 reference size, fill the shell.
    case normalizedFill
    /// AI mocks: same 02 reference aspect-fill (tall/narrow shell); may crop side bezels slightly.
    case aiMockFill
    /// AI mocks with extra horizontal zoom to trim in-screen side letterboxing.
    case aiMockFillWide(xZoom: CGFloat)
}

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

func withContext(_ rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: para
    ]
    let ns = NSString(string: text)
    let size = ns.boundingRect(
        with: NSSize(width: rect.width, height: 2000),
        options: [.usesLineFragmentOrigin],
        attributes: attrs
    ).size
    let r = NSRect(
        x: rect.minX,
        y: rect.minY + (rect.height - size.height) / 2,
        width: rect.width,
        height: size.height
    )
    ns.draw(in: r, withAttributes: attrs)
}

func cropPhoneScreenshot(
    _ src: NSImage,
    cropTop: CGFloat,
    cropBottom: CGFloat,
    cropX: CGFloat
) -> NSImage {
    let phoneW = src.size.width - cropX * 2
    let phoneH = src.size.height - cropTop - cropBottom
    let phone = makeRep(phoneW, phoneH)
    withContext(phone) {
        src.draw(
            in: NSRect(x: 0, y: 0, width: phoneW, height: phoneH),
            from: NSRect(x: cropX, y: cropBottom, width: phoneW, height: phoneH),
            operation: .copy,
            fraction: 1
        )
    }
    guard let cg = phone.cgImage else { exit(1) }
    return NSImage(cgImage: cg, size: NSSize(width: phoneW, height: phoneH))
}

/// Real screenshots: aspect-fill to the exact 02 reference bitmap size.
func normalizePhone(_ phone: NSImage, layout: ASCLayout, horizontalZoom: CGFloat = 1.0) -> NSImage {
    let targetW = layout.refPhoneW
    let targetH = layout.refPhoneH
    let normalized = makeRep(targetW, targetH)
    withContext(normalized) {
        let pw = phone.size.width
        let ph = phone.size.height
        let scale = max(targetW / pw, targetH / ph)
        let drawW = pw * scale * horizontalZoom
        let drawH = ph * scale
        let drawX = (targetW - drawW) / 2
        let drawY = (targetH - drawH) / 2
        phone.draw(
            in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
    }
    guard let cg = normalized.cgImage else { exit(1) }
    return NSImage(cgImage: cg, size: NSSize(width: targetW, height: targetH))
}

func composeASC(
    title: String,
    subtitle: String,
    phone: NSImage,
    layout: ASCLayout = .iPhone,
    contentMode: PhoneContentMode = .normalizedFill
) -> NSBitmapImageRep {
    let canvas = makeRep(layout.canvasW, layout.canvasH)
    withContext(canvas) {
        NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.047, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: layout.canvasW, height: layout.canvasH).fill()

        drawCentered(title, font: layout.titleFont, color: .white, in: layout.titleRect)
        drawCentered(
            subtitle,
            font: layout.subtitleFont,
            color: NSColor(white: 0.86, alpha: 1),
            in: layout.subtitleRect
        )

        let rect = layout.phoneDrawRect
        let pad = layout.sx(8)
        let outerR = layout.sx(48)
        let innerR = layout.sx(40)

        NSColor(white: 0.10, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX - pad, y: rect.minY - pad, width: rect.width + pad * 2, height: rect.height + pad * 2),
            xRadius: outerR,
            yRadius: outerR
        ).fill()

        let clip = NSBezierPath(roundedRect: rect, xRadius: innerR, yRadius: innerR)
        clip.addClip()

        let normalized: NSImage
        switch contentMode {
        case .normalizedFill, .aiMockFill:
            normalized = normalizePhone(phone, layout: layout)
        case .aiMockFillWide(let xZoom):
            normalized = normalizePhone(phone, layout: layout, horizontalZoom: xZoom)
        }
        normalized.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
    }
    return canvas
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to encode png\n", stderr)
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: path))
}
