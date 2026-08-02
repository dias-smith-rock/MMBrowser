import Foundation
import WebKit

enum LocationPrivacyMode: String, CaseIterable {
    case deny
    case spoof
    case ask

    var displayName: String {
        switch self {
        case .deny: return "Deny"
        case .spoof: return "Spoof"
        case .ask: return "Ask"
        }
    }

    var detail: String {
        switch self {
        case .deny: return "Sites cannot read GPS-like location"
        case .spoof: return "Sites get a virtual location you choose"
        case .ask: return "Ask each time (system location)"
        }
    }
}

struct SpoofLocationPreset: Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// IANA time zone id, e.g. America/New_York
    let timeZoneIdentifier: String

    static let all: [SpoofLocationPreset] = [
        SpoofLocationPreset(id: "nyc", name: "New York", latitude: 40.7128, longitude: -74.0060, timeZoneIdentifier: "America/New_York"),
        SpoofLocationPreset(id: "la", name: "Los Angeles", latitude: 34.0522, longitude: -118.2437, timeZoneIdentifier: "America/Los_Angeles"),
        SpoofLocationPreset(id: "london", name: "London", latitude: 51.5074, longitude: -0.1278, timeZoneIdentifier: "Europe/London"),
        SpoofLocationPreset(id: "paris", name: "Paris", latitude: 48.8566, longitude: 2.3522, timeZoneIdentifier: "Europe/Paris"),
        SpoofLocationPreset(id: "berlin", name: "Berlin", latitude: 52.5200, longitude: 13.4050, timeZoneIdentifier: "Europe/Berlin"),
        SpoofLocationPreset(id: "tokyo", name: "Tokyo", latitude: 35.6762, longitude: 139.6503, timeZoneIdentifier: "Asia/Tokyo"),
        SpoofLocationPreset(id: "singapore", name: "Singapore", latitude: 1.3521, longitude: 103.8198, timeZoneIdentifier: "Asia/Singapore"),
        SpoofLocationPreset(id: "sydney", name: "Sydney", latitude: -33.8688, longitude: 151.2093, timeZoneIdentifier: "Australia/Sydney")
    ]
}

enum GeolocationSpoof {
    struct Configuration: Equatable {
        var mode: LocationPrivacyMode
        var latitude: Double
        var longitude: Double
        var timeZoneIdentifier: String

        static func fromAppSettings() -> Configuration {
            Configuration(
                mode: AppSettings.locationPrivacyMode,
                latitude: AppSettings.spoofLatitude,
                longitude: AppSettings.spoofLongitude,
                timeZoneIdentifier: AppSettings.spoofTimeZoneIdentifier
            )
        }

        static func from(container: BrowserContainer) -> Configuration {
            Configuration(
                mode: container.locationMode,
                latitude: container.latitude,
                longitude: container.longitude,
                timeZoneIdentifier: container.timeZoneIdentifier
            )
        }
    }

    /// Injected at document start when mode is deny or spoof (global settings).
    static func userScript() -> WKUserScript? {
        userScript(configuration: .fromAppSettings())
    }

    /// Injected at document start when mode is deny or spoof.
    static func userScript(configuration: Configuration) -> WKUserScript? {
        let mode = configuration.mode
        guard mode == .deny || mode == .spoof else { return nil }

        let lat: Double
        let lon: Double
        let tz: String
        let accuracy: Double
        let deny: Bool

        switch mode {
        case .deny:
            deny = true
            lat = 0; lon = 0; tz = ""; accuracy = 0
        case .spoof:
            deny = false
            lat = configuration.latitude
            lon = configuration.longitude
            tz = configuration.timeZoneIdentifier
            accuracy = 25
        case .ask:
            return nil
        }

        let tzEscaped = tz
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let source = """
        (function() {
          if (window.__mmGeoInstalled) return;
          window.__mmGeoInstalled = true;
          var DENY = \(deny ? "true" : "false");
          var LAT = \(lat);
          var LON = \(lon);
          var ACC = \(accuracy);
          var TZ = '\(tzEscaped)';

          function fakePosition() {
            return {
              coords: {
                latitude: LAT,
                longitude: LON,
                accuracy: ACC,
                altitude: null,
                altitudeAccuracy: null,
                heading: null,
                speed: null
              },
              timestamp: Date.now()
            };
          }

          function denyError() {
            return {
              code: 1,
              message: 'User denied Geolocation',
              PERMISSION_DENIED: 1,
              POSITION_UNAVAILABLE: 2,
              TIMEOUT: 3
            };
          }

          var geo = {
            getCurrentPosition: function(success, error, options) {
              if (DENY) {
                if (typeof error === 'function') setTimeout(function() { error(denyError()); }, 0);
                return;
              }
              if (typeof success === 'function') setTimeout(function() { success(fakePosition()); }, 0);
            },
            watchPosition: function(success, error, options) {
              if (DENY) {
                if (typeof error === 'function') setTimeout(function() { error(denyError()); }, 0);
                return 0;
              }
              if (typeof success === 'function') setTimeout(function() { success(fakePosition()); }, 0);
              return 1;
            },
            clearWatch: function(id) {}
          };

          try {
            Object.defineProperty(navigator, 'geolocation', {
              configurable: true,
              get: function() { return geo; }
            });
          } catch (e) {
            try { navigator.geolocation = geo; } catch (e2) {}
          }

          if (!DENY && TZ) {
            try {
              var offsetMin = (function() {
                try {
                  var fmt = new Intl.DateTimeFormat('en-US', { timeZone: TZ, timeZoneName: 'shortOffset' });
                  var parts = fmt.formatToParts(new Date());
                  var raw = '';
                  for (var i = 0; i < parts.length; i++) {
                    if (parts[i].type === 'timeZoneName') raw = parts[i].value;
                  }
                  var m = raw.match(/GMT([+-]?)(\\d{1,2})(?::?(\\d{2}))?/);
                  if (!m) return null;
                  var sign = m[1] === '-' ? -1 : 1;
                  var h = parseInt(m[2], 10) || 0;
                  var mi = parseInt(m[3] || '0', 10) || 0;
                  return -sign * (h * 60 + mi);
                } catch (err) { return null; }
              })();
              if (offsetMin !== null) {
                Date.prototype.getTimezoneOffset = function() { return offsetMin; };
              }
              var origResolved = Intl.DateTimeFormat.prototype.resolvedOptions;
              Intl.DateTimeFormat.prototype.resolvedOptions = function() {
                var o = origResolved.apply(this, arguments);
                try { o.timeZone = TZ; } catch (e3) {}
                return o;
              };
            } catch (tzErr) {}
          }
        })();
        """

        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
