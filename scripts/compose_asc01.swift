import AppKit
import Foundation

let srcPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/image-29e476fb-ea03-40f6-b8d3-01a68c16cdb6.png"
let outPath = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/01_multiple_whatsapp.png"
let alsoPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/asc_01_whatsapp.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let srcW = src.size.width
let srcH = src.size.height

func fromY(yTop: CGFloat, height: CGFloat) -> CGFloat {
    srcH - yTop - height
}

let cropTop: CGFloat = 88
let cropBottom: CGFloat = 10
let cropX: CGFloat = 18
let phoneW = srcW - cropX * 2
let phoneH = srcH - cropTop - cropBottom

let topWebY: CGFloat = 230
let dividerY: CGFloat = 546
let bottomWebY: CGFloat = 668
let topWebH = dividerY - topWebY
let bottomWebH = (srcH - cropBottom) - bottomWebY

let phone = makeRep(phoneW, phoneH)
withContext(phone) {
    src.draw(
        in: NSRect(x: 0, y: 0, width: phoneW, height: phoneH),
        from: NSRect(x: cropX, y: cropBottom, width: phoneW, height: phoneH),
        operation: .copy,
        fraction: 1
    )

    let destWebTopInPhone = bottomWebY - cropTop
    let destWeb = NSRect(
        x: 0,
        y: phoneH - destWebTopInPhone - bottomWebH,
        width: phoneW,
        height: bottomWebH
    )
    NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.10, alpha: 1).setFill()
    destWeb.fill()

    let copyH = min(topWebH, bottomWebH)
    let srcWeb = NSRect(
        x: cropX,
        y: fromY(yTop: topWebY, height: copyH),
        width: phoneW,
        height: copyH
    )
    let destCopy = NSRect(
        x: 0,
        y: phoneH - destWebTopInPhone - copyH,
        width: phoneW,
        height: copyH
    )
    src.draw(in: destCopy, from: srcWeb, operation: .copy, fraction: 1)

    func coverPhone(x: CGFloat, yTopInOriginal: CGFloat, w: CGFloat, h: CGFloat, color: NSColor, radius: CGFloat) {
        let yTopInPhone = yTopInOriginal - cropTop
        let rect = NSRect(x: x - cropX, y: phoneH - yTopInPhone - h, width: w, height: h)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    func placeholderChat(yTopInOriginal: CGFloat) {
        let rowBG = NSColor(calibratedWhite: 0.11, alpha: 1)
        let bar = NSColor(calibratedWhite: 0.32, alpha: 1)
        let barDim = NSColor(calibratedWhite: 0.22, alpha: 1)
        coverPhone(x: 68, yTopInOriginal: yTopInOriginal, w: 390, h: 78, color: rowBG, radius: 10)
        let yTopInPhone = yTopInOriginal - cropTop
        NSColor(calibratedWhite: 0.30, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 84, y: phoneH - yTopInPhone - 16 - 42, width: 42, height: 42)).fill()
        bar.setFill()
        NSBezierPath(roundedRect: NSRect(x: 138, y: phoneH - yTopInPhone - 14 - 12, width: 92, height: 12), xRadius: 4, yRadius: 4).fill()
        barDim.setFill()
        NSBezierPath(roundedRect: NSRect(x: 138, y: phoneH - yTopInPhone - 36 - 10, width: 150, height: 9), xRadius: 3, yRadius: 3).fill()
        NSColor(calibratedWhite: 0.40, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 370, y: phoneH - yTopInPhone - 14 - 10, width: 52, height: 9), xRadius: 3, yRadius: 3).fill()
    }

    placeholderChat(yTopInOriginal: 462)
    placeholderChat(yTopInOriginal: 462 + (bottomWebY - topWebY))
}

guard let phoneCG = phone.cgImage else { exit(1) }
let phoneNS = NSImage(cgImage: phoneCG, size: NSSize(width: phoneW, height: phoneH))

let canvas = composeASC(
    title: "Multiple WhatsApp logins",
    subtitle: "Separate Web sessions—cookies don’t mix",
    phone: phoneNS
)

try writePNG(canvas, to: outPath)
try writePNG(canvas, to: alsoPath)
print("ok")
