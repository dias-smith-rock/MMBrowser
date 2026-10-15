import AppKit
import Foundation

let srcPath = "/Users/rock/Documents/Code/MMBrowser/scripts/_orig_03.png"
let outPath = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/03_switch_one_tap.png"
let alsoPath = "/Users/rock/.cursor/projects/Users-rock-Documents-Code-MMBrowser/assets/asc_03_switch.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let crop = ASCLayout.aiMockCrop03
let phone = cropPhoneScreenshot(src, cropTop: crop.top, cropBottom: crop.bottom, cropX: crop.x)

let canvas = composeASC(
    title: "Switch in one tap",
    subtitle: "Account chip jumps between identities",
    phone: phone,
    contentMode: .aiMockFill
)

try writePNG(canvas, to: outPath)
try writePNG(canvas, to: alsoPath)
print("ok")
