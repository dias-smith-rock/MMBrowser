import UIKit
import WebKit

enum LongScreenshotCapturer {
    private static let hideJS = """
    (function(){
      if (window.__mmShotHidden) return String(Math.max(
        document.documentElement.scrollHeight,
        document.body ? document.body.scrollHeight : 0
      ));
      window.__mmShotHidden = [];
      var nodes = document.querySelectorAll('*');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var s = window.getComputedStyle(el);
        if (!s) continue;
        var pos = s.position;
        if (pos !== 'fixed' && pos !== 'sticky') continue;
        window.__mmShotHidden.push([el, el.style.cssText]);
        el.style.setProperty('visibility', 'hidden', 'important');
        el.style.setProperty('opacity', '0', 'important');
        el.style.setProperty('pointer-events', 'none', 'important');
      }
      var html = document.documentElement;
      var body = document.body;
      return String(Math.max(
        html ? html.scrollHeight : 0,
        body ? body.scrollHeight : 0,
        html ? html.offsetHeight : 0,
        body ? body.offsetHeight : 0
      ));
    })();
    """

    private static let restoreJS = """
    (function(){
      var list = window.__mmShotHidden || [];
      for (var i = 0; i < list.length; i++) {
        try { list[i][0].style.cssText = list[i][1]; } catch (e) {}
      }
      window.__mmShotHidden = null;
      return true;
    })();
    """

    private static let readyStateJS = "document.readyState"
    private static let viewportImagesReadyJS = """
    (function(){
      var imgs = document.images || [];
      var pending = 0;
      for (var i = 0; i < imgs.length; i++) {
        var img = imgs[i];
        var r = img.getBoundingClientRect();
        if (r.bottom < -20 || r.top > (window.innerHeight + 20)) continue;
        if (!img.complete || img.naturalWidth === 0) pending++;
      }
      return pending === 0 ? '1' : '0';
    })();
    """

    static func capture(from webView: WKWebView, completion: @escaping (UIImage?) -> Void) {
        waitUntilPageReady(webView: webView, attempt: 0) {
            beginCapture(from: webView, completion: completion)
        }
    }

    /// Captures the current viewport after the page has finished loading.
    static func captureViewport(from webView: WKWebView, completion: @escaping (UIImage?) -> Void) {
        waitUntilPageReady(webView: webView, attempt: 0) {
            waitForViewportPaint(webView: webView, attempt: 0) {
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(origin: .zero, size: webView.bounds.size)
                webView.takeSnapshot(with: config) { image, _ in
                    DispatchQueue.main.async {
                        guard let image = image else {
                            completion(nil)
                            return
                        }
                        if isMostlyBlank(image) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                webView.takeSnapshot(with: config) { retry, _ in
                                    DispatchQueue.main.async { completion(retry ?? image) }
                                }
                            }
                            return
                        }
                        completion(image)
                    }
                }
            }
        }
    }

    /// Wait for navigation + DOM complete before any snapshot (avoids black/white frames).
    private static func waitUntilPageReady(webView: WKWebView, attempt: Int, completion: @escaping () -> Void) {
        let maxAttempts = 60 // ~12s
        let loading = webView.isLoading || webView.estimatedProgress < 0.99

        if loading && attempt < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                waitUntilPageReady(webView: webView, attempt: attempt + 1, completion: completion)
            }
            return
        }

        webView.evaluateJavaScript(readyStateJS) { result, _ in
            let state = (result as? String) ?? ""
            if state != "complete" && attempt < maxAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    waitUntilPageReady(webView: webView, attempt: attempt + 1, completion: completion)
                }
                return
            }
            // Extra paint settle after load completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: completion)
        }
    }

    private static func beginCapture(from webView: WKWebView, completion: @escaping (UIImage?) -> Void) {
        let scrollView = webView.scrollView
        let originalOffset = scrollView.contentOffset
        let originalIndicator = scrollView.showsVerticalScrollIndicator
        scrollView.showsVerticalScrollIndicator = false

        webView.evaluateJavaScript(hideJS) { result, _ in
            let jsHeight = (result as? String).flatMap(Double.init).map { CGFloat($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                captureTiles(
                    webView: webView,
                    scrollView: scrollView,
                    pageHeightHint: jsHeight,
                    originalOffset: originalOffset,
                    originalIndicator: originalIndicator,
                    completion: completion
                )
            }
        }
    }

    private static func captureTiles(
        webView: WKWebView,
        scrollView: UIScrollView,
        pageHeightHint: CGFloat?,
        originalOffset: CGPoint,
        originalIndicator: Bool,
        completion: @escaping (UIImage?) -> Void
    ) {
        let viewport = webView.bounds.size
        guard viewport.width > 1, viewport.height > 1 else {
            finish(webView: webView, scrollView: scrollView, offset: originalOffset, indicator: originalIndicator, image: nil, completion: completion)
            return
        }

        let contentHeight = max(pageHeightHint ?? 0, scrollView.contentSize.height, viewport.height)
        let maxHeight = min(contentHeight, viewport.height * 15)

        let topCrop = min(110, floor(viewport.height * 0.20))
        let bottomCrop = min(88, floor(viewport.height * 0.16))
        let step = max(48, viewport.height - topCrop - bottomCrop)

        var images: [UIImage] = []
        var offset: CGFloat = 0

        func clampedY(_ y: CGFloat) -> CGFloat {
            let maxY = max(0, scrollView.contentSize.height - viewport.height)
            return min(max(y, 0), maxY)
        }

        func snapshotTile(retry: Int, isFirst: Bool, isLast: Bool, remaining: CGFloat, done: @escaping () -> Void) {
            waitForViewportPaint(webView: webView, attempt: 0) {
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(origin: .zero, size: viewport)

                webView.takeSnapshot(with: config) { image, _ in
                    DispatchQueue.main.async {
                        guard var snapshot = image else {
                            done()
                            return
                        }

                        // Blank frame → short wait and retry once.
                        if isMostlyBlank(snapshot), retry < 2 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                snapshotTile(retry: retry + 1, isFirst: isFirst, isLast: isLast, remaining: remaining, done: done)
                            }
                            return
                        }

                        if isLast && remaining > 0 && remaining < viewport.height {
                            snapshot = crop(snapshot, y: 0, height: remaining) ?? snapshot
                        }
                        snapshot = trimTile(
                            snapshot,
                            isFirst: isFirst,
                            isLast: isLast,
                            topCrop: topCrop,
                            bottomCrop: bottomCrop
                        )
                        if snapshot.size.height > 1 {
                            images.append(snapshot)
                        }
                        done()
                    }
                }
            }
        }

        func next() {
            if offset >= maxHeight - 1 {
                let stitched = stitch(images)
                finish(
                    webView: webView,
                    scrollView: scrollView,
                    offset: originalOffset,
                    indicator: originalIndicator,
                    image: stitched,
                    completion: completion
                )
                return
            }

            let y = offset
            let isFirst = images.isEmpty
            let remaining = maxHeight - y
            let isLast = remaining <= step + 1 || y + viewport.height >= maxHeight - 1

            scrollView.setContentOffset(CGPoint(x: 0, y: clampedY(y)), animated: false)

            // Let WKWebView commit the new scroll position before snapshot.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                snapshotTile(retry: 0, isFirst: isFirst, isLast: isLast, remaining: remaining) {
                    if isLast {
                        offset = maxHeight
                    } else {
                        offset += step
                    }
                    next()
                }
            }
        }

        scrollView.setContentOffset(.zero, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            next()
        }
    }

    /// Wait until in-viewport images are decoded / complete.
    private static func waitForViewportPaint(webView: WKWebView, attempt: Int, completion: @escaping () -> Void) {
        let maxAttempts = 20 // ~4s
        webView.evaluateJavaScript(viewportImagesReadyJS) { result, _ in
            let ready = (result as? String) == "1"
            if ready || attempt >= maxAttempts {
                // One more frame for CSS/layout after images.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                waitForViewportPaint(webView: webView, attempt: attempt + 1, completion: completion)
            }
        }
    }

    /// Detect near solid black/white snapshots from incomplete compositor frames.
    private static func isMostlyBlank(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let w = min(cg.width, 32)
        let h = min(cg.height, 32)
        guard w > 0, h > 0 else { return true }

        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var dark = 0
        var light = 0
        let total = w * h
        for i in 0..<total {
            let o = i * 4
            let r = Int(data[o])
            let g = Int(data[o + 1])
            let b = Int(data[o + 2])
            let lum = (r + g + b) / 3
            if lum < 12 { dark += 1 }
            if lum > 243 { light += 1 }
        }
        let ratio = Double(max(dark, light)) / Double(total)
        return ratio > 0.96
    }

    private static func trimTile(
        _ image: UIImage,
        isFirst: Bool,
        isLast: Bool,
        topCrop: CGFloat,
        bottomCrop: CGFloat
    ) -> UIImage {
        var y: CGFloat = 0
        var h = image.size.height
        if !isFirst {
            y = min(topCrop, h - 1)
            h -= y
        }
        if !isLast {
            h -= min(bottomCrop, h - 1)
        }
        return crop(image, y: y, height: max(1, h)) ?? image
    }

    private static func crop(_ image: UIImage, y: CGFloat, height: CGFloat) -> UIImage? {
        let scale = image.scale
        let h = min(height, image.size.height - y)
        guard h > 1, let cg = image.cgImage else { return nil }
        let pixel = CGRect(
            x: 0,
            y: y * scale,
            width: image.size.width * scale,
            height: h * scale
        )
        guard let cut = cg.cropping(to: pixel) else { return nil }
        return UIImage(cgImage: cut, scale: scale, orientation: image.imageOrientation)
    }

    private static func stitch(_ images: [UIImage]) -> UIImage? {
        guard !images.isEmpty else { return nil }
        let width = images.map { $0.size.width }.max() ?? 0
        let height = images.reduce(CGFloat(0)) { $0 + $1.size.height }
        guard width > 1, height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = images.first?.scale ?? UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var y: CGFloat = 0
            for image in images {
                image.draw(in: CGRect(x: 0, y: y, width: image.size.width, height: image.size.height))
                y += image.size.height
            }
        }
    }

    private static func finish(
        webView: WKWebView,
        scrollView: UIScrollView,
        offset: CGPoint,
        indicator: Bool,
        image: UIImage?,
        completion: @escaping (UIImage?) -> Void
    ) {
        webView.evaluateJavaScript(restoreJS) { _, _ in
            scrollView.showsVerticalScrollIndicator = indicator
            scrollView.setContentOffset(offset, animated: false)
            completion(image)
        }
    }
}
