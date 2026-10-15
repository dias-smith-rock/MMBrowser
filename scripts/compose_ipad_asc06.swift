import AppKit
import Foundation

let layout = ASCLayout.iPad
let outDir = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/ipad"
let srcPath = "/Users/rock/Documents/Code/MMBrowser/website/assets/appstore/06_work_stays.png"
let outPath = "\(outDir)/06_work_stays.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("failed to load source\n", stderr)
    exit(1)
}

// 06 is a finished AI marketing frame; crop the phone mock region from it.
let cropTop: CGFloat = 250
let cropBottom: CGFloat = 16
let cropX: CGFloat = 70
let phone = cropPhoneScreenshot(src, cropTop: cropTop, cropBottom: cropBottom, cropX: cropX)

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas = composeASC(
    title: "Work stays at work",
    subtitle: "Email & docs in a dedicated identity",
    phone: phone,
    layout: layout,
    contentMode: .aiMockFill
)

try writePNG(canvas, to: outPath)
print("ok \(outPath)")
