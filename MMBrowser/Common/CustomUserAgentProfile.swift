import Foundation
import WebKit

enum ClientHintBrand: String, Codable, CaseIterable {
    case chrome124
    case chrome131
    case chrome136
    case edge124
    case safari18

    var displayName: String {
        switch self {
        case .chrome124: return "Google Chrome 124"
        case .chrome131: return "Google Chrome 131"
        case .chrome136: return "Google Chrome 136"
        case .edge124: return "Microsoft Edge 124"
        case .safari18: return "Safari 18"
        }
    }

    var majorVersion: String {
        switch self {
        case .chrome124, .edge124: return "124"
        case .chrome131: return "131"
        case .chrome136: return "136"
        case .safari18: return "18"
        }
    }

    var fullVersion: String {
        switch self {
        case .chrome124: return "124.0.6367.60"
        case .chrome131: return "131.0.6778.108"
        case .chrome136: return "136.0.7103.93"
        case .edge124: return "124.0.2478.67"
        case .safari18: return "18.0"
        }
    }

    var greaseBrand: String { "Not-A.Brand" }

    var primaryBrand: String {
        switch self {
        case .chrome124, .chrome131, .chrome136: return "Google Chrome"
        case .edge124: return "Microsoft Edge"
        case .safari18: return "Safari"
        }
    }

    var secondaryBrand: String {
        switch self {
        case .safari18: return "AppleWebKit"
        default: return "Chromium"
        }
    }

    /// Low-entropy `Sec-CH-UA` value.
    var secCHUA: String {
        "\"\(primaryBrand)\";v=\"\(majorVersion)\", \"\(secondaryBrand)\";v=\"\(majorVersion)\", \"\(greaseBrand)\";v=\"99\""
    }

    var fullVersionList: String {
        "\"\(primaryBrand)\";v=\"\(fullVersion)\", \"\(secondaryBrand)\";v=\"\(fullVersion)\", \"\(greaseBrand)\";v=\"10.0.1.4\""
    }

    var isChromiumFamily: Bool {
        self != .safari18
    }
}

enum ClientHintPlatform: String, Codable, CaseIterable {
    case windows
    case macOS
    case android
    case iOS
    case linux

    var displayName: String {
        switch self {
        case .windows: return "Windows"
        case .macOS: return "macOS"
        case .android: return "Android"
        case .iOS: return "iOS"
        case .linux: return "Linux"
        }
    }

    var secCHUAPlatform: String { "\"\(displayName)\"" }
}

enum ClientHintModel: String, Codable, CaseIterable {
    case none
    case pixel8
    case pixel9
    case iphone
    case iphone16
    case galaxyS24
    case surfaceLaptop
    case surfacePro
    case macbook

    var displayName: String {
        switch self {
        case .none: return "Don’t send"
        case .pixel8: return "Pixel 8"
        case .pixel9: return "Pixel 9"
        case .iphone: return "iPhone"
        case .iphone16: return "iPhone 16"
        case .galaxyS24: return "Samsung Galaxy S24"
        case .surfaceLaptop: return "Surface Laptop"
        case .surfacePro: return "Surface Pro"
        case .macbook: return "MacBook"
        }
    }

    var headerValue: String? {
        switch self {
        case .none: return nil
        case .pixel8: return "Pixel 8"
        case .pixel9: return "Pixel 9"
        case .iphone, .iphone16: return "iPhone"
        case .galaxyS24: return "SM-S921B"
        case .surfaceLaptop: return "Surface Laptop"
        case .surfacePro: return "Surface Pro"
        case .macbook: return "MacBook"
        }
    }

    /// Desktop Chrome on Windows/macOS/Linux usually sends an empty model.
    static func options(for platform: ClientHintPlatform) -> [ClientHintModel] {
        switch platform {
        case .windows:
            return [.none, .surfaceLaptop, .surfacePro]
        case .macOS:
            return [.none, .macbook]
        case .linux:
            return [.none]
        case .android:
            return [.none, .pixel8, .pixel9, .galaxyS24]
        case .iOS:
            return [.none, .iphone, .iphone16]
        }
    }
}

enum ClientHintArchitecture: String, Codable, CaseIterable {
    case none
    case x86
    case arm

    var displayName: String {
        switch self {
            case .none: return "Don’t send"
            case .x86: return "Intel or AMD"
            case .arm: return "ARM"
        }
    }

    var headerValue: String? {
        switch self {
        case .none: return nil
        case .x86: return "x86"
        case .arm: return "arm"
        }
    }
}

/// Structured Custom UA: Client Hints pickers, persisted per tab.
struct CustomUserAgentProfile: Equatable, Codable {
    var brand: ClientHintBrand
    var isMobile: Bool
    var platform: ClientHintPlatform
    var includeFullVersionList: Bool
    var model: ClientHintModel
    var architecture: ClientHintArchitecture

    static let `default` = CustomUserAgentProfile(
        brand: .chrome124,
        isMobile: true,
        platform: .iOS,
        includeFullVersionList: false,
        model: .iphone,
        architecture: .arm
    )

    var summary: String {
        "\(brand.displayName) · \(platform.displayName) · \(isMobile ? "Phone" : "Computer")"
    }

    var userAgentString: String {
        let version = brand.fullVersion
        switch brand {
        case .safari18:
            return safariUserAgent()
        case .chrome124, .chrome131, .chrome136, .edge124:
            return chromiumUserAgent(full: version)
        }
    }

    private func safariUserAgent() -> String {
        if platform == .iOS || (platform == .macOS && isMobile) {
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        }
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    }

    private func chromiumUserAgent(full: String) -> String {
        let edgeSuffix = brand == .edge124 ? " Edg/\(full)" : ""
        if isMobile {
            switch platform {
            case .android:
                let device = model.headerValue ?? "Pixel 8"
                return "Mozilla/5.0 (Linux; Android 14; \(device)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(full) Mobile Safari/537.36\(edgeSuffix)"
            case .iOS:
                return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/\(full) Mobile/15E148 Safari/604.1"
            default:
                return "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(full) Mobile Safari/537.36\(edgeSuffix)"
            }
        }
        switch platform {
        case .windows:
            let archToken = architecture == .arm ? "ARM64" : "Win64; x64"
            return "Mozilla/5.0 (Windows NT 10.0; \(archToken)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(full) Safari/537.36\(edgeSuffix)"
        case .macOS:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(full) Safari/537.36\(edgeSuffix)"
        case .linux:
            let archToken = architecture == .arm ? "aarch64" : "x86_64"
            return "Mozilla/5.0 (X11; Linux \(archToken)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(full) Safari/537.36\(edgeSuffix)"
        case .android:
            let device = model.headerValue ?? "Pixel 8"
            return "Mozilla/5.0 (Linux; Android 14; \(device)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(full) Safari/537.36\(edgeSuffix)"
        case .iOS:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/\(full) Safari/604.1"
        }
    }
}

extension IdentitySpoof {
    static func clientHintsUserScript(for profile: CustomUserAgentProfile) -> WKUserScript {
        let ua = jsString(profile.userAgentString)
        let platform = jsString(profile.platform.displayName)
        let brandsJSON = profile.brand.brandsJSON(full: false)
        let fullJSON = profile.brand.brandsJSON(full: true)
        let mobile = profile.isMobile ? "true" : "false"
        let model = jsString(profile.model.headerValue ?? "")
        let arch = jsString(profile.architecture.headerValue ?? "")
        let includeFull = profile.includeFullVersionList ? "true" : "false"
        let includeModel = profile.model != .none ? "true" : "false"
        let includeArch = profile.architecture != .none ? "true" : "false"
        let vendor = profile.brand.isChromiumFamily ? "Google Inc." : "Apple Computer, Inc."
        let navPlatform: String = {
            switch profile.platform {
            case .windows: return profile.architecture == .arm ? "Win32" : "Win32"
            case .macOS: return "MacIntel"
            case .android: return "Linux armv8l"
            case .iOS: return "iPhone"
            case .linux: return profile.architecture == .arm ? "Linux aarch64" : "Linux x86_64"
            }
        }()

        let source = """
        (function() {
          var UA = \(ua);
          var PLATFORM = '\(navPlatform)';
          var VENDOR = '\(vendor)';
          var BRANDS = \(brandsJSON);
          var FULL = \(fullJSON);
          var MOBILE = \(mobile);
          var HINT_PLATFORM = \(platform);
          var MODEL = \(model);
          var ARCH = \(arch);
          var INCLUDE_FULL = \(includeFull);
          var INCLUDE_MODEL = \(includeModel);
          var INCLUDE_ARCH = \(includeArch);
          try {
            Object.defineProperty(navigator, 'userAgent', { get: function() { return UA; }, configurable: true });
            Object.defineProperty(navigator, 'appVersion', { get: function() { return UA.replace(/^Mozilla\\/\\d\\.\\d\\s/, ''); }, configurable: true });
            Object.defineProperty(navigator, 'platform', { get: function() { return PLATFORM; }, configurable: true });
            Object.defineProperty(navigator, 'vendor', { get: function() { return VENDOR; }, configurable: true });
          } catch (e) {}
          var uaData = {
            brands: BRANDS,
            mobile: MOBILE,
            platform: HINT_PLATFORM,
            getHighEntropyValues: function(hints) {
              var out = { brands: BRANDS, mobile: MOBILE, platform: HINT_PLATFORM };
              var list = hints || [];
              for (var i = 0; i < list.length; i++) {
                var h = list[i];
                if (h === 'fullVersionList' && INCLUDE_FULL) out.fullVersionList = FULL;
                if (h === 'uaFullVersion' && INCLUDE_FULL && FULL.length) out.uaFullVersion = FULL[0].version;
                if (h === 'model' && INCLUDE_MODEL) out.model = MODEL;
                if (h === 'architecture' && INCLUDE_ARCH) out.architecture = ARCH;
                if (h === 'platformVersion') out.platformVersion = '';
                if (h === 'bitness') out.bitness = (ARCH === 'x86' ? '64' : '');
              }
              return Promise.resolve(out);
            },
            toJSON: function() { return { brands: BRANDS, mobile: MOBILE, platform: HINT_PLATFORM }; }
          };
          try {
            Object.defineProperty(navigator, 'userAgentData', { get: function() { return uaData; }, configurable: true });
          } catch (e) {}
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }
}

private extension ClientHintBrand {
    func brandsJSON(full: Bool) -> String {
        let version = full ? fullVersion : majorVersion
        let grease = full ? "10.0.1.4" : "99"
        func item(_ brand: String, _ ver: String) -> String {
            "{brand:'\(brand)',version:'\(ver)'}"
        }
        return "[\(item(primaryBrand, version)),\(item(secondaryBrand, version)),\(item(greaseBrand, grease))]"
    }
}
