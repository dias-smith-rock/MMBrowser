import AppKit
import Foundation

let layout = ASCLayout.iPad
let outDir = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/ipad"
let srcPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/image-f4794f24-3b95-48f6-ae1b-36c6c1d93868.png"
let outPath = "\(outDir)/02_instagram_telegram.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let crop = ASCLayout.phoneUICrop
let phone = cropPhoneScreenshot(src, cropTop: crop.top, cropBottom: crop.bottom, cropX: crop.x)

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas = composeASC(
    title: "Instagram & Telegram too",
    subtitle: "Plus Facebook—each account stays isolated",
    phone: phone,
    layout: layout
)

try writePNG(canvas, to: outPath)
print("ok \(outPath)")
