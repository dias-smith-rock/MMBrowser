import AppKit
import Foundation

let srcPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/image-f4794f24-3b95-48f6-ae1b-36c6c1d93868.png"
let outPath = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/02_instagram_telegram.png"
let alsoPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/asc_02_instagram_telegram.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let crop = ASCLayout.phoneUICrop
let phone = cropPhoneScreenshot(src, cropTop: crop.top, cropBottom: crop.bottom, cropX: crop.x)

let canvas = composeASC(
    title: "Instagram & Telegram too",
    subtitle: "Plus Facebook—each account stays isolated",
    phone: phone
)

try writePNG(canvas, to: outPath)
try writePNG(canvas, to: alsoPath)
print("ok")
