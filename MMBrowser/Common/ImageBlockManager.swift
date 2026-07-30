import Foundation
import WebKit

/// Blocks network images/videos and shows a centered chip to turn off no-image mode.
final class ImageBlockManager {
    static let shared = ImageBlockManager()
    static let disableHandlerName = "mmDisableNoImages"

    private let ruleListID = "MMBrowserImageBlock"
    private var cachedList: WKContentRuleList?
    private var isCompiling = false
    private var waiters: [(WKContentRuleList?) -> Void] = []

    var isEnabled: Bool {
        get { AppSettings.noImagesEnabled }
        set { AppSettings.noImagesEnabled = newValue }
    }

    /// Document-start script: gate imgs/videos and overlay a centered “Turn off No Images” chip.
    static let placeholderUserScript = WKUserScript(
        source: placeholderJS,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    private init() {}

    func apply(to configuration: WKWebViewConfiguration, completion: @escaping () -> Void) {
        let finish: (WKContentRuleList?) -> Void = { [weak self] list in
            if let list = list {
                configuration.userContentController.add(list)
            }
            if self?.isEnabled == true {
                configuration.userContentController.addUserScript(Self.placeholderUserScript)
            }
            completion()
        }
        guard isEnabled else {
            DispatchQueue.main.async { finish(nil) }
            return
        }
        DispatchQueue.main.async {
            self.resolveRuleList(completion: finish)
        }
    }

    private func resolveRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let cached = cachedList {
            completion(cached)
            return
        }
        waiters.append(completion)
        guard !isCompiling else { return }
        isCompiling = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ruleListID,
            encodedContentRuleList: Self.ruleJSON
        ) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("[ImageBlock] compile failed: \(error.localizedDescription)")
                }
                self.cachedList = list
                self.isCompiling = false
                let pending = self.waiters
                self.waiters.removeAll()
                pending.forEach { $0(list) }
            }
        }
    }

    private static let ruleJSON: String = {
        let rules: [[String: Any]] = [
            [
                "trigger": [
                    "url-filter": ".*",
                    "resource-type": ["image"]
                ],
                "action": ["type": "block"]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: rules, options: [])
        return String(data: data, encoding: .utf8)!
    }()

    private static let placeholderJS = """
    (function() {
      if (window.__mmImageBlockInstalled) return;
      window.__mmImageBlockInstalled = true;

      var STYLE_ID = 'mm-noimg-style';
      var CHIP_TEXT = 'Turn off No Images';
      var MIN_W = 120;
      var MIN_H = 44;
      var VIDEO_MIN_H = 120;
      var MAX_W = 360;
      var MAX_H = 240;
      var VIDEO_MAX_H = 280;

      function ensureStyle() {
        var existing = document.getElementById(STYLE_ID);
        if (existing) existing.remove();
        var s = document.createElement('style');
        s.id = STYLE_ID;
        s.textContent = ''
          + '.mm-noimg-wrap{position:relative!important;display:flex!important;'
          + 'align-items:center!important;justify-content:center!important;'
          + 'width:100%;height:100%;'
          + 'max-width:min(100%,360px)!important;max-height:240px!important;'
          + 'min-width:120px!important;min-height:44px!important;'
          + 'box-sizing:border-box!important;overflow:hidden!important;'
          + 'background:transparent!important;border:none!important;border-radius:0!important;'
          + 'padding:0!important;margin:0!important;vertical-align:middle!important;}'
          + '.mm-noimg-wrap.mm-novid{min-height:120px!important;max-height:280px!important;}'
          + '.mm-noimg-wrap img,.mm-noimg-wrap video{position:absolute!important;left:0!important;top:0!important;'
          + 'right:0!important;bottom:0!important;width:100%!important;height:100%!important;'
          + 'opacity:0!important;display:block!important;margin:0!important;padding:0!important;'
          + 'max-width:none!important;pointer-events:none!important;z-index:0!important;}'
          + '.mm-noimg-chip{position:relative!important;top:auto!important;left:auto!important;'
          + 'right:auto!important;bottom:auto!important;inset:auto!important;'
          + 'transform:none!important;flex:0 0 auto!important;'
          + 'display:inline-flex!important;align-items:center!important;justify-content:center!important;'
          + 'height:28px!important;width:auto!important;max-width:calc(100% - 16px)!important;'
          + 'padding:0 12px!important;margin:0!important;border:none!important;border-radius:14px!important;'
          + 'background:rgba(60,60,67,0.78)!important;color:#ffffff!important;'
          + 'font:500 12px/28px -apple-system,BlinkMacSystemFont,sans-serif!important;'
          + 'pointer-events:auto!important;z-index:20!important;cursor:pointer!important;'
          + 'box-shadow:0 1px 4px rgba(0,0,0,0.18)!important;white-space:nowrap!important;'
          + 'overflow:hidden!important;text-overflow:ellipsis!important;opacity:1!important;}';
        (document.head || document.documentElement).appendChild(s);
      }

      function absoluteURL(url) {
        try { return new URL(url, document.baseURI).href; } catch (e) { return url; }
      }

      function pickImgSrc(img) {
        return img.getAttribute('src')
          || img.getAttribute('data-src')
          || img.getAttribute('data-original')
          || img.getAttribute('data-lazy-src')
          || img.getAttribute('data-url')
          || '';
      }

      function pickVideoSrc(video) {
        var direct = video.getAttribute('src')
          || video.getAttribute('data-src')
          || video.getAttribute('data-original')
          || '';
        if (direct) return direct;
        var sources = video.querySelectorAll('source');
        for (var i = 0; i < sources.length; i++) {
          var s = sources[i].getAttribute('src')
            || sources[i].getAttribute('data-src')
            || '';
          if (s) return s;
        }
        return '';
      }

      function stashVideoSources(video) {
        video.querySelectorAll('source').forEach(function(el) {
          el.removeAttribute('src');
          el.removeAttribute('data-src');
        });
      }

      function attrPair(el) {
        var aw = parseFloat(el.getAttribute('width'));
        var ah = parseFloat(el.getAttribute('height'));
        if (aw > 0 && ah > 0) return { w: aw, h: ah };
        return null;
      }

      function minHFor(wrap) {
        return wrap.classList.contains('mm-novid') ? VIDEO_MIN_H : MIN_H;
      }

      function maxHFor(wrap) {
        return wrap.classList.contains('mm-novid') ? VIDEO_MAX_H : MAX_H;
      }

      function maxWFor() {
        var vw = (window.innerWidth || document.documentElement.clientWidth || MAX_W) - 24;
        if (vw < MIN_W) vw = MIN_W;
        return Math.min(MAX_W, vw);
      }

      function clampSize(wrap) {
        if (!wrap) return;
        var minH = minHFor(wrap);
        var maxH = maxHFor(wrap);
        var maxW = maxWFor();
        wrap.style.minWidth = MIN_W + 'px';
        wrap.style.minHeight = minH + 'px';
        wrap.style.maxWidth = maxW + 'px';
        wrap.style.maxHeight = maxH + 'px';
        var wr = wrap.getBoundingClientRect();
        var w = wr.width;
        var h = wr.height;
        if (w < MIN_W) w = MIN_W;
        if (h < minH) h = minH;
        if (w > maxW) w = maxW;
        if (h > maxH) h = maxH;
        wrap.style.width = Math.round(w) + 'px';
        wrap.style.height = Math.round(h) + 'px';
      }

      function hardenSize(wrap, media) {
        if (!wrap || !media) return;
        var minH = minHFor(wrap);
        var maxH = maxHFor(wrap);
        var maxW = maxWFor();

        function applyBox(w, h) {
          wrap.style.display = 'flex';
          wrap.style.alignItems = 'center';
          wrap.style.justifyContent = 'center';
          wrap.style.width = Math.round(Math.min(maxW, Math.max(MIN_W, w))) + 'px';
          wrap.style.height = Math.round(Math.min(maxH, Math.max(minH, h))) + 'px';
          clampSize(wrap);
        }

        var parent = wrap.parentElement;
        if (parent) {
          var pr = parent.getBoundingClientRect();
          var pcs = window.getComputedStyle(parent);
          var explicitH = pcs.height && pcs.height !== 'auto' && parseFloat(pcs.height) > 0;
          var explicitW = pcs.width && pcs.width !== 'auto' && parseFloat(pcs.width) > 0;
          if (pr.width >= 8 && pr.height >= 8 && (explicitH || explicitW || parent.childElementCount <= 2)) {
            applyBox(pr.width, pr.height);
            return;
          }
        }

        var wr = wrap.getBoundingClientRect();
        if (wr.width >= 8 && wr.height >= 8) {
          applyBox(wr.width, wr.height);
          return;
        }

        var pair = attrPair(media);
        if (pair) {
          wrap.style.aspectRatio = pair.w + ' / ' + pair.h;
          applyBox(pair.w, pair.h);
          return;
        }

        var cs = window.getComputedStyle(media);
        var cw = parseFloat(cs.width);
        var ch = parseFloat(cs.height);
        if (cw >= 8 && ch >= 8) {
          applyBox(cw, ch);
          return;
        }

        var fallbackW = (parent && parent.getBoundingClientRect().width) || cw || MIN_W;
        var ratio = wrap.classList.contains('mm-novid') ? 0.56 : 0.28;
        applyBox(fallbackW, Math.max(minH, fallbackW * ratio));
      }

      function scheduleHarden(wrap, media) {
        hardenSize(wrap, media);
        requestAnimationFrame(function() {
          hardenSize(wrap, media);
          requestAnimationFrame(function() { hardenSize(wrap, media); });
        });
        setTimeout(function() { hardenSize(wrap, media); }, 0);
        setTimeout(function() { hardenSize(wrap, media); }, 300);
        setTimeout(function() { hardenSize(wrap, media); }, 1000);
      }

      function requestDisableNoImages(e) {
        if (e) {
          e.preventDefault();
          e.stopPropagation();
        }
        if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmDisableNoImages) {
          webkit.messageHandlers.mmDisableNoImages.postMessage({});
        }
      }

      function makeChip() {
        var chip = document.createElement('span');
        chip.className = 'mm-noimg-chip';
        chip.setAttribute('role', 'button');
        chip.setAttribute('aria-label', CHIP_TEXT);
        chip.textContent = CHIP_TEXT;
        // Inline styles so site CSS cannot push the chip off-center.
        chip.style.cssText = ''
          + 'position:relative;top:auto;left:auto;right:auto;bottom:auto;'
          + 'transform:none;display:inline-flex;align-items:center;justify-content:center;'
          + 'height:28px;width:auto;max-width:calc(100% - 16px);padding:0 12px;margin:0;'
          + 'border:none;border-radius:14px;background:rgba(60,60,67,0.78);color:#fff;'
          + 'font:500 12px/28px -apple-system,BlinkMacSystemFont,sans-serif;'
          + 'pointer-events:auto;z-index:20;cursor:pointer;white-space:nowrap;'
          + 'box-shadow:0 1px 4px rgba(0,0,0,0.18);flex:0 0 auto;';
        chip.addEventListener('click', requestDisableNoImages, true);
        return chip;
      }

      function makeWrap(isVideo) {
        var wrap = document.createElement('span');
        wrap.className = isVideo ? 'mm-noimg-wrap mm-novid' : 'mm-noimg-wrap';
        wrap.setAttribute('aria-label', CHIP_TEXT);
        wrap.style.cssText = ''
          + 'position:relative;display:flex;align-items:center;justify-content:center;'
          + 'box-sizing:border-box;overflow:hidden;background:transparent;'
          + 'border:none;border-radius:0;padding:0;margin:0;';
        var chip = makeChip();
        return { wrap: wrap, chip: chip };
      }

      function wrapImg(img) {
        if (!img || img.dataset.mmNoimg === '1' || img.closest('.mm-noimg-wrap')) return;
        var raw = pickImgSrc(img);
        if (!raw || raw.indexOf('data:') === 0 || raw.indexOf('blob:') === 0) return;
        var w = img.getAttribute('width');
        var h = img.getAttribute('height');
        if (w && h && parseInt(w, 10) < 8 && parseInt(h, 10) < 8) return;

        ensureStyle();
        img.dataset.mmNoimg = '1';
        img.removeAttribute('src');
        img.removeAttribute('srcset');
        img.removeAttribute('data-src');

        var parts = makeWrap(false);
        var wrap = parts.wrap;
        if (img.parentNode) {
          img.parentNode.insertBefore(wrap, img);
          wrap.appendChild(img);
          wrap.appendChild(parts.chip);
        }
        scheduleHarden(wrap, img);
      }

      function wrapVideo(video) {
        if (!video || video.dataset.mmNoimg === '1' || video.closest('.mm-noimg-wrap')) return;
        stashVideoSources(video);
        ensureStyle();
        video.dataset.mmNoimg = '1';

        try { video.pause(); } catch (e) {}
        video.removeAttribute('autoplay');
        video.autoplay = false;
        video.preload = 'none';
        video.removeAttribute('src');
        video.removeAttribute('data-src');
        if (video.getAttribute('poster')) video.removeAttribute('poster');
        if (video.style && video.style.backgroundImage) video.style.backgroundImage = 'none';

        var parts = makeWrap(true);
        var wrap = parts.wrap;
        if (video.parentNode) {
          video.parentNode.insertBefore(wrap, video);
          wrap.appendChild(video);
          wrap.appendChild(parts.chip);
        }
        scheduleHarden(wrap, video);

        video.addEventListener('play', function(e) {
          e.preventDefault();
          try { video.pause(); } catch (err) {}
        }, true);
      }

      function scan(root) {
        ensureStyle();
        var scope = root && root.querySelectorAll ? root : document;
        if (root && root.tagName === 'IMG') { wrapImg(root); return; }
        if (root && root.tagName === 'VIDEO') { wrapVideo(root); return; }
        scope.querySelectorAll('img').forEach(wrapImg);
        scope.querySelectorAll('video').forEach(wrapVideo);
      }

      function hardenAll() {
        document.querySelectorAll('.mm-noimg-wrap').forEach(function(wrap) {
          var media = wrap.querySelector('img, video');
          if (media) hardenSize(wrap, media);
        });
      }

      function boot() {
        scan(document);
        hardenAll();
        var mo = new MutationObserver(function(mutations) {
          for (var i = 0; i < mutations.length; i++) {
            var nodes = mutations[i].addedNodes;
            for (var j = 0; j < nodes.length; j++) {
              var n = nodes[j];
              if (!n || n.nodeType !== 1) continue;
              if (n.tagName === 'IMG') wrapImg(n);
              else if (n.tagName === 'VIDEO') wrapVideo(n);
              else if (n.querySelectorAll) {
                n.querySelectorAll('img').forEach(wrapImg);
                n.querySelectorAll('video').forEach(wrapVideo);
              }
            }
          }
        });
        mo.observe(document.documentElement || document, { childList: true, subtree: true });
        window.addEventListener('load', hardenAll);
        window.addEventListener('resize', hardenAll);
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
      } else {
        boot();
      }
    })();
    """
}
