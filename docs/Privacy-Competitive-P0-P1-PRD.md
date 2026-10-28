# Privacy competitive gaps — P0 / P1 PRD

**Context:** Competitive read of [TechBloat — 7 Best Privacy-Focused Browsers for iPhone (2026)](https://www.techbloat.com/7-best-privacy-focused-browsers-for-iphone-2026.html) vs XBrowser positioning (*privacy browser + multi-account Spaces*; honest limits: no IP change / anonymity / antidetect).

**Goal:** Reach “review-table checkmarks” for everyday privacy (P0), then trust & default-browser conversion (P1), without drifting into VPN/Tor/fingerprint-spoofing.

**Out of scope (explicit non-goals):** Built-in VPN, Tor routing, aggressive fingerprint spoofing/randomization marketed as anonymity.

**Premium note:** Unless marked Premium, ship on Free. Space Lock remains Premium.

---

## Summary backlog

| ID | Priority | Feature | Primary outcome |
| --- | --- | --- | --- |
| P0-1 | P0 | Page privacy report (shield detail) | Visible protection like Brave/DDG |
| P0-2 | P0 | One-tap Erase / Fire | Shared-phone & disposable-session parity |
| P0-3 | P0 | Privacy search defaults | Private Search checkbox on review tables |
| P0-4 | P0 | Cookie / site-data controls clarity | Cookie-control narrative + actions |
| P1-1 | P1 | “What we collect” transparency page + Settings link | Minimal-telemetry trust |
| P1-2 | P1 | Stronger Set as Default browser funnel | Links don’t leak to Safari |
| P1-3 | P1 | Blocking list quality + recovery UX | Credible default blocking |

Each item below: problem → requirements → acceptance → **English UI/settings copy** → analytics (optional).

---

# P0

## P0-1 — Page privacy report (shield detail)

### Problem
Competitors show *what* was blocked (Shields / site grade). XBrowser has a shield but weak “report” affordance for reviews and user trust.

### Requirements
1. Tapping the address-bar **shield** opens a sheet: **Privacy report** for the current page (not a buried Settings-only screen).
2. Show at least:
   - Protection on/off for this page (reflects global + per-page override)
   - Approximate **blocked request count** for this page load (reuse existing block counting when available; if heavy scan is off, show network-level count and label it honestly)
   - Short category breakdown when possible (e.g. Ads, Trackers, Other) — best-effort; hide empty categories
   - Link: **Blocking settings**
   - Link: **Erase browsing data…** (opens P0-2 flow)
3. Honest footer line: blocking is best-effort; does not hide IP / anonymize.
4. If blocking is off globally or for this page, sheet explains how to turn it on.

### Acceptance
- [ ] Shield tap → report sheet on any normal tab.
- [ ] Count updates after navigation / reload when blocking is on.
- [ ] Copy never claims “blocks all trackers” or anonymity.
- [ ] Feature catalog updated when shipped.

### English UI / settings copy

| Surface | Copy |
| --- | --- |
| Sheet title | Privacy report |
| Subtitle | What XBrowser blocked on this page |
| Stat label | Blocked requests |
| Section | Categories |
| Toggle (if shown) | Block ads & trackers on this page |
| Link | Blocking settings |
| Link | Erase browsing data… |
| Footer | Blocking reduces many ads and trackers. It does not change your IP or make you anonymous. |
| Empty / blocking off | Blocking is off for this page. Turn it on to reduce trackers and ads. |
| CTA | Turn on blocking |

**Settings → Blocking** (section header stay as today if exists; ensure):

| Key | Copy |
| --- | --- |
| Title | Block Ads & Trackers |
| Footer | Filter lists can update when sites change. Protection is best-effort. |

---

## P0-2 — One-tap Erase (Fire / clear data)

### Problem
DuckDuckGo Fire Button and Firefox Focus erase are review magnets for shared phones. XBrowser has per-Space isolation but no prominent “wipe now” ritual.

### Requirements
1. Entry points:
   - Tab switcher / Spaces chrome: **Erase**
   - Privacy report sheet link
   - Settings → Privacy → **Erase browsing data**
2. Action sheet / screen with clear scope:
   - **This Space** (default)
   - **All Spaces** (destructive; confirm)
3. Data types (checkboxes, sensible defaults checked):
   - Cookies and site data
   - History
   - Cache
   - Optional unchecked: Bookmarks, Downloads (Downloads are app-wide — label as shared)
4. After erase of current Space: stay on that Space with empty session (new tab / home), toast confirmation.
5. Private Browsing: offer **Close all private tabs** (align with existing private behavior); do not pretend Private = network anonymity.
6. Do not erase Space Lock secrets / App Lock credentials.

### Acceptance
- [ ] Erase This Space clears that Space’s WKWebsiteDataStore-backed site data + history (and cache as selected).
- [ ] Erase All Spaces requires typed confirm or two-step alert.
- [ ] Bookmarks only cleared if user opts in.
- [ ] Copy distinguishes Space vs app-wide Downloads.

### English UI / settings copy

| Surface | Copy |
| --- | --- |
| Button | Erase |
| Screen title | Erase browsing data |
| Scope | This Space |
| Scope | All Spaces |
| Helper (This Space) | Clears data for “{Space name}” only. Other Spaces stay signed in. |
| Helper (All Spaces) | Clears browsing data in every Space. You will be signed out of sites in all Spaces. |
| Checkbox | Cookies and site data |
| Checkbox | History |
| Checkbox | Cached files |
| Checkbox | Bookmarks |
| Checkbox | Downloads (shared across Spaces) |
| Primary button | Erase |
| Confirm All Spaces | Erase data in all Spaces? This cannot be undone. |
| Confirm button | Erase everything |
| Cancel | Cancel |
| Toast | Browsing data erased |
| Settings row | Erase browsing data |

**Settings → Privacy** group label: `Privacy`

---

## P0-3 — Privacy search defaults

### Problem
Review tables treat “private search” as a column. XBrowser supports many engines but doesn’t spotlight privacy-preserving defaults.

### Requirements
1. Settings → Search: group engines under **Privacy-friendly** vs **General** (ordering only; all remain selectable).
2. Privacy-friendly includes at least: DuckDuckGo, Brave Search (if already in list), and any no-profile options already shipped.
3. Onboarding / first-run (or first open of Search settings): optional card **Choose a privacy-friendly search engine** with DuckDuckGo as recommended default suggestion (user can skip / keep Google).
4. Do not force-change existing users’ engine silently; only prompt once (dismissible, “Don’t ask again”).

### Acceptance
- [ ] New installs can pick DDG (or current privacy default) in ≤2 taps from onboarding card.
- [ ] Existing users are not silently switched.
- [ ] Website/App Store can truthfully say “supports privacy-friendly search engines (e.g. DuckDuckGo).”

### English UI / settings copy

| Surface | Copy |
| --- | --- |
| Settings section | Search engine |
| Group header | Privacy-friendly |
| Group header | General |
| Onboarding title | Choose your search engine |
| Onboarding body | Privacy-friendly options like DuckDuckGo help reduce search profiling. You can change this anytime in Settings. |
| Recommended badge | Recommended |
| Primary | Continue |
| Secondary | Not now |
| Re-prompt Settings footer | Used for address-bar search. |

---

## P0-4 — Cookie / site-data controls clarity

### Problem
Article checklist includes cookie controls and easy site-data clearing. Isolation exists per Space; UX messaging and per-site clear are under-exposed.

### Requirements
1. Settings → Privacy short explainer:
   - Cookies & site data are **per Space**
   - Tabs in one Space share that Space’s jar
2. Page menu or long-press site in history: **Clear data for this site** (current Space only).
3. Link from Privacy report → Clear data for this site.
4. Optional later: cross-site cookie note in report (“Third-party requests blocked when possible”) — only if technically accurate with current blocker.

### Acceptance
- [ ] User can clear one site’s data for the active Space without erasing the whole Space.
- [ ] In-product copy matches catalog (Space ≠ per-tab isolation).

### English UI / settings copy

| Surface | Copy |
| --- | --- |
| Settings footer | Cookies, cache, history, and bookmarks are stored per Space. Tabs in the same Space share that Space’s data. |
| Action | Clear data for this site |
| Confirm | Clear cookies and site data for {domain} in this Space? |
| Toast | Site data cleared |
| Education title | How Spaces isolate data |
| Education body | Each Space has its own cookies and site data—like separate browser profiles on one phone. |

---

# P1

## P1-1 — “What we collect” transparency (in-app + site)

### Problem
Reviewers emphasize minimal telemetry and clear diagnostics toggles.

### Requirements
1. **Website:** `/privacy-data/` or section on existing privacy policy page titled **What XBrowser collects** (short, scannable). Prefer dedicated short page linked from footer + Settings.
2. **Settings → Privacy → What we collect** opens in-app WebView or native bullets mirroring the site.
3. List in plain language: e.g. crash reports / analytics (Firebase if used), Remote Config, purchase receipts via Apple — and **what is not** sent (browsing history, Space contents, passwords).
4. If diagnostics are optional, expose toggle with English label; default per current shipping behavior (document actual default in PR).

### Acceptance
- [ ] One tap from Settings to human-readable collection summary.
- [ ] Site page indexed / linked from privacy policy “Summary”.
- [ ] No contradiction with `privacy.html`.

### English UI / settings copy

| Surface | Copy |
| --- | --- |
| Settings row | What we collect |
| Screen title | What we collect |
| Intro | XBrowser is built so most browsing data stays on your device. Here’s what leaves the device, if anything. |
| Section | On your device |
| Bullet | History, cookies, and Space data stay local unless you erase them or back up via OS features you control. |
| Section | Optional / operational |
| Bullet | Crash reports and usage analytics (if enabled) help us fix bugs and improve the app. |
| Bullet | App Store handles Premium purchases; we don’t see your full payment card details. |
| Section | We don’t |
| Bullet | We don’t sell your browsing history. |
| Bullet | Spaces don’t send your passwords to XBrowser servers for sync (state actual architecture). |
| Link | Full Privacy Policy |
| Toggle (if applicable) | Share crash & analytics data |
| Toggle footer | Helps improve stability. Never required for core browsing. |

### Website draft — short page outline (English)

**URL:** `https://xxxxxbrowser.cc/privacy-data/`  
**Title:** What XBrowser Collects  
**H1:** What XBrowser collects (and what stays on your iPhone)

Body sections: On-device by default · Operational services · Purchases · What we don’t do · Contact (`support@xxxxxbrowser.cc`) · Link to full Privacy Policy.

---

## P1-2 — Set as Default browser funnel

### Problem
Article: if Mail/Messages open Safari, real-world privacy drops.

### Requirements
1. Settings row **Default browser** with status: On / Off (best-effort detection).
2. After onboarding day 1–3, or after user creates 2nd Space, soft prompt once: **Open links in XBrowser**.
3. Deep link / open iOS settings instructions (system limitation: cannot force default).
4. Success criteria: user completes system toggle; dismissible forever.

### Acceptance
- [ ] Clear path documented for current iOS version.
- [ ] Prompt frequency capped (≤1 auto prompt / install unless user re-enables tips).

### English UI / settings copy

| Surface | Copy |
| --- | --- |
| Settings row | Default browser |
| Status on | On |
| Status off | Off — links may open in Safari |
| Button | Open iPhone Settings |
| Instructions | Settings → Apps → XBrowser → Default Browser App → XBrowser |
| Prompt title | Open links in XBrowser |
| Prompt body | Keep Spaces, blocking, and locks when you tap links from Mail or Messages. |
| Primary | Open Settings |
| Secondary | Not now |

---

## P1-3 — Blocking list quality + recovery UX

### Problem
Brave/DDG win on “it just works.” XBrowser already has filters + updates; needs user-visible recovery when sites break or lists go stale.

### Requirements
1. Settings → Blocking: **Update filters** (manual) + last-updated timestamp.
2. When auto-update exists, show **Updated {date}** / **Up to date**.
3. Broken-site path: Privacy report or page menu → **Allow ads & trackers on this site** (per-site allow) + **Report issue** (email/`support@` prefilled subject — no new backend required).
4. Keep remote kill-switch / script update paths for YouTube experiments as today; don’t surface experimental claims on the privacy report.

### Acceptance
- [ ] User can refresh filters without reinstalling.
- [ ] Per-site allow is reversible.
- [ ] Catalog/docs remain honest (“best-effort”).

### English UI / settings copy

| Surface | Copy |
| --- | --- |
| Row | Filter lists |
| Button | Update now |
| Status | Last updated: {date} |
| Status | Up to date |
| Action | Allow ads & trackers on this site |
| Action | Block on this site |
| Report | Report a broken site… |
| Mail subject | Broken site with blocking: {domain} |

---

# Website — competitive comparison table (draft)

Use on `/privacy-browser-iphone/` and/or a new `/compare/` section. **Tone:** calm, factual, no “#1”. Emphasize Spaces + locks; concede VPN/Tor to specialists.

### Intro copy (English)

**H2:** How XBrowser compares to popular privacy browsers on iPhone  

**Lead:** On iOS, every browser uses WebKit. The differences are defaults, blocking, search, and whether you get lasting identity isolation. XBrowser focuses on tracker blocking plus Spaces you can lock—not VPN or anonymity claims.

### Table draft

| | XBrowser | Brave | DuckDuckGo | Safari (+ blocker) | Aloha |
| --- | --- | --- | --- | --- | --- |
| Built-in ad & tracker blocking | Yes (best-effort) | Strong defaults | Strong, simple | Via content blockers | Yes |
| Privacy-friendly search options | Yes (e.g. DuckDuckGo) | Brave Search | DuckDuckGo default | User choice | User choice |
| Persistent multi-account Spaces (separate cookie jars) | **Yes — core** | No (profiles limited vs Spaces) | No | Profiles ≠ full parallel jars like Spaces | No |
| Split View with two Spaces | **Yes** | — | — | — | — |
| Lock one identity (Space Lock) | **Yes (Premium)** | App/private tab style differs | Fire clears data | Private tabs + Face ID | App-oriented |
| Decoy / Second Lock | **Yes** | — | — | — | — |
| One-tap erase browsing data | **Planned P0** / Yes when shipped | Partial | Fire Button | Clear History & Data | Varies |
| On-page privacy report | **Planned P0** / Yes when shipped | Shields | Site grade | Limited | Varies |
| Built-in VPN | No (use system VPN / Relay) | Paid optional | Privacy Pro (regions) | iCloud Private Relay | Built-in focus |
| Claims anonymity / changes IP | **No** | VPN separate | VPN separate | Relay optional | VPN marketing varies |
| In-app ad monetization | **No** | Rewards/optional model differs | Minimal | N/A | Freemium |

**Footnote:** Comparison is simplified for iPhone. Features change by version and region. XBrowser does not change your IP and is not an antidetect browser.

### Closing CTA copy

Keep identities apart with Spaces, reduce trackers while you browse, and lock what matters—without pretending to be a VPN.  

[Download on the App Store] · [How Spaces work](/multiple-accounts-browser/) · [Privacy browser for iPhone](/privacy-browser-iphone/)

---

# Delivery plan (suggested)

| Sprint | Ship |
| --- | --- |
| Sprint 1 | P0-2 Erase + P0-4 Clear site data + copy |
| Sprint 2 | P0-1 Privacy report sheet + P0-3 search grouping/onboarding |
| Sprint 3 | P1-1 transparency page + Settings row; P1-2 default browser prompt |
| Sprint 4 | P1-3 filter update UX + broken-site allow/report; publish comparison table on site |

**Catalog:** When any item ships, update `docs/XBrowser-Feature-Catalog.md` in the same PR (workspace rule).

**Success metrics (lightweight):**
- Shield → report open rate
- Erase completions / week
- Search engine mix (% on DuckDuckGo etc.)
- Default-browser Settings open rate
- Support tickets: “how do I clear data / shared phone”

---

# Open questions (resolve before Sprint 1)

1. Exact telemetry toggles today (Firebase Analytics on/off?) — must match P1-1 copy.  
2. Block count source for report: network filter only vs optional heavy page scan (CPU).  
3. Erase All Spaces: require Premium Face ID confirm or available to Free? (Recommend: available to Free.)  
4. Comparison table: publish now with “Coming soon” on Erase/Report, or wait until P0 ships?
