# XBrowser Feature Catalog

Product positioning: **multi-identity / multi-account browser** (login isolation, no cookie mixing).  
YouTube experience, ad blocking, and the built-in player are **important product capabilities** and strong **acquisition hooks**, but they are not the primary brand identity.

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
| **Private Browsing** | Incognito tabs that do not use normal Space libraries the same way; downloads disabled in Private. |

### 1.2 Protection for identities (locks)

| Feature | Description |
| --- | --- |
| **App Lock** | Lock the whole app on launch / after background with PIN, pattern, and optional biometrics. |
| **Second Lock (decoy)** | Alternate unlock that opens a decoy session and keeps locked Spaces / lock entry points hidden. |
| **Space Lock** | PIN/pattern lock for an individual Space. **Premium.** Locked Spaces stay hidden under Second Lock sessions. |

### 1.3 Essential browsing

| Feature | Description |
| --- | --- |
| **Tabs** | Open, switch, and manage tabs (including address-bar swipe between page tabs). |
| **Address bar (search / URL)** | Search with the selected engine or open a URL; supports keyboard shortcut chips (e.g. `https://`, `.com`). |
| **History suggestions** | Address-bar suggestions from recent visits (deduped by site for autocomplete). |
| **Bookmarks** | Save and open bookmarks (isolated per Space). |
| **History** | Browsing history (isolated per Space). |
| **Default browser** | Promote / open system settings to set XBrowser as the default browser app. |
| **Search engines** | Choose Google, DuckDuckGo, Bing, Amazon, TikTok, YouTube, ChatGPT, Gemini, and similar. |
| **HTTPS First** | Prefer HTTPS navigation by default. |
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

### 2.1 Ads & tracker blocking

| Feature | Description |
| --- | --- |
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
| **Watch Later** | Save videos/pages to watch later (isolated per Space), with offline-oriented options where applicable. |
| **Reader Mode** | Simplified reading view for articles. |
| **Find on Page** | Search text within the current page. |
| **Translate** | Open translation for the current page (e.g. via Google Translate flow). |
| **Text size** | Adjust page text size. |
| **User Agent** | Override browser user agent for the tab/site when needed. |
| **Long screenshot** | Capture a tall screenshot of page content. |
| **Save as PDF** | Export the page as a PDF. |
| **Passwords** | Saved passwords vault (isolated per Space), with unlock gating. |

### 2.6 Privacy utilities (beyond Spaces)

| Feature | Description |
| --- | --- |
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
| **Onboarding** | First-run carousel focused on multi WhatsApp/IG and clean multi-shop use; may demo Split View. |
| **Tips** | Lightweight UX tips (e.g. address-bar tab swipe). |
| **What's New / about copy** | In-app feature summary strings for releases and settings. |

---

## 3. Quick reference

| Tier | Role in product/marketing |
| --- | --- |
| **Core — Spaces & locks** | Primary identity and Premium story |
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

---

*Generated from the XBrowser / MMBrowser iOS product surface. UI strings in the app remain English.*
