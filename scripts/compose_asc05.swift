import AppKit
import Foundation

let srcPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/image-f97ce6a3-4a9f-4822-8832-f1c41264d0aa.png"
let outPath = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/05_shops_separate.png"
let alsoPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/asc_05_shops.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let crop = ASCLayout.phoneUICrop
let phone = cropPhoneScreenshot(src, cropTop: crop.top, cropBottom: crop.bottom, cropX: crop.x)

let canvas = composeASC(
    title: "Each account has its own home",
    subtitle: "Shortcuts, cookies, and history stay with Work",
    phone: phone
)

try writePNG(canvas, to: outPath)
try writePNG(canvas, to: alsoPath)
print("ok")
