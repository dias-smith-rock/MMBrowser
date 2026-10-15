import AppKit
import Foundation

let layout = ASCLayout.iPad
let outDir = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/ipad"
let srcPath = "/Users/rock/Documents/Code/MMBrowser/scripts/_orig_04.png"
let outPath = "\(outDir)/04_split_view.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

let crop = ASCLayout.aiMockCrop04
let phone = cropPhoneScreenshot(src, cropTop: crop.top, cropBottom: crop.bottom, cropX: crop.x)

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas = composeASC(
    title: "Split View proof",
    subtitle: "Two accounts, same site, zero crossover",
    phone: phone,
    layout: layout,
    contentMode: .aiMockFillWide(xZoom: 0.85)
)

try writePNG(canvas, to: outPath)
print("ok \(outPath)")
