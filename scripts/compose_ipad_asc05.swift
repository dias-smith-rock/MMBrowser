import AppKit
import Foundation

let layout = ASCLayout.iPad
let outDir = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/ipad"
let srcPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/image-f97ce6a3-4a9f-4822-8832-f1c41264d0aa.png"
let outPath = "\(outDir)/05_shops_separate.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let crop = ASCLayout.phoneUICrop
let phone = cropPhoneScreenshot(src, cropTop: crop.top, cropBottom: crop.bottom, cropX: crop.x)

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas = composeASC(
    title: "Each account has its own home",
    subtitle: "Shortcuts, cookies, and history stay with Work",
    phone: phone,
    layout: layout
)

try writePNG(canvas, to: outPath)
print("ok \(outPath)")
