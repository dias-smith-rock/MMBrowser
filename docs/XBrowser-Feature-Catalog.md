# XBrowser Feature Catalog

Product positioning: **dual primary** — a **private browser** and a **multi-account browser**. Ads and trackers are blocked by default; Spaces keep logins from mixing.  
YouTube experience and the built-in player remain strong acquisition hooks, not a third brand identity.  
Honest boundary: isolation, blocking, and local locks — not a VPN, not IP anonymity, and not “blocks all trackers.”

This document lists **core** vs **non-core** features. Each row is one user-facing capability with a short description.  
Premium (current): unlimited Spaces + Space Lock. Free tier includes up to **3** Spaces.

---

## 1. Core features

Capabilities that define XBrowser’s identity, or that are essential to being a credible daily browser.

### 1.1 Multi-identity (Spaces)

| Feature | Description |
| --- | --- |
| **Spaces** | Separate browsing identities. Each Space keeps its own cookies, site data, history, bookmarks, tabs, Watch Later, Reading List, and passwords so accounts do not mix. |
| **Space switcher** | Quick switch between Spaces from browser chrome (space chip / account UI) without losing isolation. |
| **Space Hub / home per Space** | Per-Space home surface with favorites and space-oriented entry points. |
| **Favorites (per Space)** | Home shortcuts (e.g. WhatsApp, Instagram, Facebook) scoped to the active Space. |
| **Manage Spaces** | Create, rename, and delete Spaces. Creating beyond the free cap requires Premium. |
| **Isolated vs Shared explanation** | In-product education: what is isolated per Space vs shared app-wide (e.g. Downloads). |
| **Split View (dual Space)** | Two panes at once, each bound to a different Space—useful for dual WhatsApp/IG or comparing two logins. |
| **Private Browsing** | Incognito tabs that do not keep history, cookies, or site data after they are closed; downloads off. Does not hide network IP. |

### 1.2 Protection for identities (locks)

| Feature | Description |
| --- | --- |
| **App Lock** | Lock the whole app on launch / after background with PIN, pattern, and optional biometrics. |
| **Second Lock (decoy / secondary password)** | Alternate App Lock PIN or pattern (must differ from the primary). Unlocking with it opens a decoy session where locked Spaces and lock feature entry points stay completely hidden. |
| **Space Lock** | PIN/pattern lock for an individual Space. **Premium.** Locked Spaces stay hidden under Second Lock sessions. |

### 1.3 Essential browsing

| Feature | Description |
| --- | --- |
| **Tabs** | Open, switch, and manage tabs (including address-bar swipe between page tabs). |
| **Address bar (search / URL)** | Search with the selected engine or open a URL; supports keyboard shortcut chips (e.g. `https://`, `.com`). |
| **History suggestions** | Address-bar suggestions from recent visits (deduped by site for autocomplete). |
| **Bookmarks** | Save and open bookmarks (isolated per Space). |
| **History** | Browsing history (isolated per Space). |
| **Default browser** | Settings row with best-effort Off status (iOS does not report the default browser), iPhone Settings instructions, and one dismissible prompt after day 1–3 or a second Space. |
| **Search engines** | Privacy-friendly (DuckDuckGo) and General groups. One-time picker does not change an existing engine until Continue. |
| **HTTPS First** | Prefer HTTPS navigation by default; no automatic HTTP fallback. |
| **Downloads** | App-wide shared download list (not per Space); unavailable in Private Browsing. |
| **Home ↔ page Back restore** | After leaving a webpage via Home (or Back-to-Home), Back on the home screen can return to that page tab. |

### 1.4 Premium (current membership)

| Feature | Description |
| --- | --- |
| **Unlimited Spaces** | Remove the free 3-Space limit. |
| **Space Lock** | Per-Space PIN/pattern protection (see above). |
| **Paywall / trial** | Subscription paywall, restore purchases, optional cold-start present. |

---

## 2. Non-core features

Valuable for acquisition, retention, or polish. Listed in full so media, ads, Web Editor, and tools are not collapsed into vague buckets.

### 2.1 Ads & tracker blocking / ad-free product

| Feature | Description |
| --- | --- |
| **Ad-free product chrome** | XBrowser does not monetize with in-app ads (no AdMob-style banners / interstitials / app-open ads in the app UI). Optional Premium is App Store subscription. |
| **Block Ads & Trackers** | Blocks ad/tracker network requests and hides common on-page ad banners. Toggle in Settings; address-bar shield reflects protection. |
| **Accurate Block Count** | Optional shield badge that counts blocks via a heavier page scan (uses more CPU). |
| **Filter updates** | Downloadable/updatable filter packs so blocking can recover after site changes. |
| **Per-page ad block toggle** | Turn ad blocking on/off for the current page from the page menu without changing the global setting. |

### 2.2 YouTube & video-site hooks

| Feature | Description |
| --- | --- |
| **Hide Shorts (Focus Mode)** | Hides YouTube Shorts shelves and redirects Shorts links to reduce distraction. |
| **Fewer YouTube Video Ads** | Experimental, best-effort reduction of YouTube in-player ads (pre-roll / mid-roll style payloads). May stop working when YouTube changes; remote kill-switch / script updates supported. |
| **YouTube video ad auto-skip** | When a skippable ad UI appears, automatically taps the skip control (alongside payload filtering). Part of the YouTube Ad Shield behavior. |
| **YouTube dark appearance** | Applies a dark look when browsing YouTube. |
| **YouTube filter degraded notice** | Toast/notice path when anti-adblock / locked player behavior is detected so the user knows filtering degraded. |

### 2.3 Built-in video player (custom PiP / AV player)

Native player used for supported streams (alongside system PiP where applicable).

| Feature | Description |
| --- | --- |
| **Picture in Picture (system)** | System/WK Picture in Picture for supported web video when enabled in Settings. |
| **Custom floating player** | In-app floating AV player window over the browser (drag, resize/window sizes, dock to screen edge). |
| **Return to page** | Jump back from the floating player to the underlying page. |
| **Floating play / pause** | Play or pause from the floating chrome. |
| **Skip back / forward 10s** | Rewind or forward about 10 seconds from floating or fullscreen chrome. |
| **Playback speed** | Speed menu (e.g. 0.5x–3x, including 0.75 / 1.25 / 1.5) on floating and fullscreen players. |
| **Progress scrubbing** | Seek via progress bar / gestures on the floating player. |
| **Volume gesture (floating)** | Adjust volume from the floating player chrome. |
| **Expand to fullscreen player** | Open the shared AVPlayer in an in-app fullscreen player. |
| **Fullscreen controls** | Fullscreen overlay: close, play/pause, ±10s, speed, scrubber, elapsed/remaining time. |
| **Hide Toolbar (immersive)** | Manually hide address bar + toolbar for H5 games / fixed pages (address-bar icon or page menu); restore via top-right “Exit Immersive”. |
| **Fullscreen brightness / volume gestures** | Vertical drag on left/right regions to adjust brightness (where supported) or system volume. |
| **Fullscreen controls lock** | Side lock button to block accidental taps; only unlock remains available until unlocked. |
| **Sleep Timer** | Pause playback automatically after 10 / 15 / 30 / 45 / 60 minutes or a custom duration; available on floating and fullscreen players (middle-right control). |
| **Sticky Picture in Picture** | Prefer keeping PiP / advancing to the next video when sticky mode is on (including background handoff helpers). |
| **Background Audio** | Keep supported video/audio playing after leaving the app (Settings toggle; works with media keep-alive paths). |
| **Manual PiP from menu** | Start custom/system PiP from the page/tools menu when a stream is available. |

### 2.4 Web Editor

| Feature | Description |
| --- | --- |
| **Web Editor mode** | Enter pick mode from the rich menu / address-bar cleaner bar (“Web Editor”) to customize the current page. |
| **This site / This page scope** | Choose whether new hide/edit rules apply to the whole site or only the current page URL. |
| **Element pick & highlight** | Tap page elements to select the smallest practical text/control under the finger (not always the whole row). |
| **Delete (hide element)** | Hide the selected element and save a persistent hide rule (session-only in Private). |
| **Edit text** | Change the selected element’s visible text; saves a persistent edit rule (session-only in Private) and reapplies on later loads. |
| **Reset** | Clear Web Editor rules that apply to the current page/site context and reload so the page returns to its original state. |
| **Rules list** | Open saved Web Editor rules (from the Web Editor title or Settings); preview hide rules when a snapshot exists. |
| **Single / batch / clear rules** | Swipe-delete one rule, multi-select delete, or clear all rules. |
| **Reapply on load** | Hide CSS and text edits are reapplied when matching pages load (with short retries for late-rendered DOM). |

### 2.5 Libraries & productivity

| Feature | Description |
| --- | --- |
| **Reading List** | Save pages for later; supports offline-oriented saving (isolated per Space). |
| **Watch Later** | Save videos/pages to watch later (isolated per Space), with offline-oriented options where applicable. Empty list shows an intro and how-to (menu → Add to Watch Later; Background Audio tip). |
| **Reader Mode** | Simplified reading view for articles. |
| **Find on Page** | Search text within the current page. |
| **Translate** | Open translation for the current page (e.g. via Google Translate flow). |
| **Text size** | Adjust page text size. |
| **User Agent** | Override browser user agent for the tab/site when needed. |
| **Screenshot** | Capture the current page viewport and open the built-in editor (crop shapes, annotate, save). |
| **Long screenshot** | Capture a tall screenshot of page content (scroll + stitch beyond the viewport), then edit/save. |
| **Save as PDF** | Export the page as a PDF. |
| **Passwords** | Saved passwords vault (isolated per Space), with unlock gating. |

### 2.6 Privacy utilities (beyond Spaces)

| Feature | Description |
| --- | --- |
| **Privacy Report** | Shield sheet for the current page: protection on/off, measured block count when Accurate Block Count is on, Blocking settings, Erase, and clear-this-site. Best-effort; does not hide IP. |
| **Erase browsing data** | One-tap erase for This Space (default) or All Spaces, from the tab switcher (fire icon), Privacy report, and Settings. A full-page burn plays for about 1.5s, then the cleared page opens. Optional bookmarks and shared Downloads. Private mode closes private tabs. Does not erase App Lock or Space Lock. |
| **Clear data for this site** | Page menu and Privacy report clear one site’s cookies and site data in the current Space only. |
| **Per-site blocking exception** | Allow or block ads and trackers for the current site without changing the global switch. Reversible. Report a broken site opens mail to support. |
| **What we collect** | Settings page and xxxxxbrowser.cc/privacy-data/ describe on-device data, optional Firebase crash/analytics (on by default), and what is not sent. |
| **Filter list recovery** | Settings shows Up to date or Last updated, with Update now. |
| **Global Privacy Control** | Sends Sec-GPC and `navigator.globalPrivacyControl` so sites can treat the visit as opted out of sale or sharing. On by default; toggle in Settings. |
| **Dangerous site warning** | Blocks lookalike / phishing-style hosts on main-frame and popup loads. Go Back is recommended; Continue is explicit. |
| **Recommended for privacy** | Settings checklist for private-friendly toggles. Does not turn on Clear Option or wipe logins. |
| **Location privacy** | When sites ask for location: deny, use current, or spoof a virtual/custom city (GPS-like APIs only—not network IP). Global and per-Space. |
| **Block Images** | Browse without loading images. |
| **Aggressive image block** | Also scrub images inside iframes (heavier). |
| **Clear Option** | Auto-clear selected data (cache, cookies, history, local storage, etc.) when leaving the app. |
| **Close All Tabs on Exit** | Optional reset to a fresh New Tab when leaving the app. |
| **Tab preview images** | Optional thumbnails in the tab switcher. |
| **Active Background Tabs limit** | Cap how many recently used tabs keep a live WebView in memory (LRU unload of the rest). |
| **Clear browsing data** | Manual clear flows for stored browsing data. |
| **Privacy Explained** | In-app privacy positioning and isolation explanation. |

### 2.7 Appearance & onboarding

| Feature | Description |
| --- | --- |
| **Themes** | Theme packs (e.g. Default, Minimal, Cute, Steady, Feminine). |
| **Home wallpaper** | Home background colors / wallpaper options. |
| **Background gallery** | Additional background choices. |
| **Onboarding (Feature Highlights)** | First-run Highlights lead with private-by-default protections, then Spaces, locks, and background playback. Split View Wow waits until the first toolbar page-menu tap. No auto VIP paywall (and home crown hidden) on the install calendar day. |
| **Tips** | Lightweight UX tips (address-bar tab swipe; post-onboarding ads shield and Background Audio toasts for new users). |
| **What's New / about copy** | In-app feature summary strings for releases and settings. |

---

## 3. Quick reference

| Tier | Role in product/marketing |
| --- | --- |
| **Core — Private + Spaces** | Dual primary: blocked-by-default browsing and isolated accounts |
| **Core — Essential browsing** | Table stakes so XBrowser feels like a real browser |
| **Non-core — Ads / YouTube / Player / Web Editor** | Strong hooks and retention; list explicitly in store & content |
| **Non-core — Libraries & tools** | Completeness and power-user depth |
| **Non-core — Appearance** | Personalization; low differentiation |

---

## 4. Notes for future Premium expansion

Today only **unlimited Spaces** and **Space Lock** are Premium-gated.  
Candidates often discussed for membership later: deeper locks, Web Editor sync/limits, video/player Pro, richer privacy packs.  
Keep a clear **free “aha” path** (enough Spaces + dual-login demo) so marketing stays honest.

---

## 5. Compliance wording (hooks)

When describing YouTube ad reduction / auto-skip publicly:

- Prefer: *Fewer YouTube interruptions*, *best-effort*, *experimental*.
- Avoid: *ad-free YouTube*, *guaranteed no ads*, *blocks all video ads*.

When describing the product as ad-free:

- Prefer: *private by default*, *ads and trackers blocked*, *accounts never mix*, *no in-app ads*, *HTTPS First*, *not a VPN*.
- Keep clear: product chrome is ad-free; website blocking is best-effort; Spaces do not change your IP; YouTube video ads may still appear.

---

*Generated from the XBrowser / MMBrowser iOS product surface. UI strings in the app remain English.*
