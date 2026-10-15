import AppKit
import Foundation

let layout = ASCLayout.iPad
let outDir = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/ipad"
let srcPath = "/Users/rock/Documents/Code/MMBrowser/scripts/_orig_03.png"
let outPath = "\(outDir)/03_switch_one_tap.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let crop = ASCLayout.aiMockCrop03
let phone = cropPhoneScreenshot(src, cropTop: crop.top, cropBottom: crop.bottom, cropX: crop.x)

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas = composeASC(
    title: "Switch in one tap",
    subtitle: "Account chip jumps between identities",
    phone: phone,
    layout: layout,
    contentMode: .aiMockFill
)

try writePNG(canvas, to: outPath)
print("ok \(outPath)")
