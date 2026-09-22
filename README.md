# HVAC Leads

A personal, on-device CRM for tracking HVAC job applications. It searches
OpenStreetMap for HVAC companies within a radius of your home, lets you save
contact info and notes, and tracks where each application stands — all
stored locally on your phone, no account or backend required.

## How it works

- **Search** — set your home address once (Settings), pick a radius, and tap
  "Search Nearby." The app searches two sources and merges the results:
  the free OpenStreetMap Overpass API (HVAC-tagged businesses and businesses
  whose name mentions HVAC/heating/cooling), and a bundled snapshot of
  Seattle-area business license records (see "Seattle business license
  data" below) — plotted together on a map and a list, each tagged with
  where it came from.
- **Track** — save any result (or add one manually for word-of-mouth leads)
  and track it through statuses: Not Contacted → Researching → Applied →
  Interview Scheduled → Interviewed → Offer/Rejected/Not Interested. Every
  status change is logged with a timestamp and optional note.
- **Contact info** — OpenStreetMap's tagging is community-maintained, so
  phone/email are often missing. The Company Detail screen has a "Try to
  find phone/email from website" button that does a best-effort scrape of
  the company's own homepage for a `tel:`/`mailto:` link.
- **Backup** — there's no cloud sync. Settings → Export lets you save all
  companies to CSV or JSON and share/back them up whenever you want.
- **Updates** — this app is sideloaded, not installed from the Play Store,
  so it checks GitHub Releases for this repo on launch and can download and
  install a newer version itself. See "Releasing updates" below.

## Project structure

```
lib/
  models/      Company, StatusHistoryEntry, HomeLocation, ApplicationStatus
  services/    DatabaseService (sqflite), GeocodingService (Nominatim),
               OverpassService, LicenseDataService (bundled license data),
               EnrichmentService, ExportService, UpdateService (GitHub Releases)
  screens/     Search/Map, Company List, Company Detail, Add Manual Company,
               Export, Settings
  widgets/     UpdateBanner (startup update check)
  utils/       distance.dart (haversine), version_compare.dart
assets/data/   Bundled Seattle-area business license snapshot (see below)
scripts/       geocode_license_data.py — one-off geocoding for that snapshot
test/          Unit tests for the above (no device/emulator needed)
.github/workflows/release.yml           Builds + signs + publishes a release APK
.github/workflows/geocode-license-data.yml  One-off: geocodes the license snapshot
```

## Seattle business license data

`assets/data/seattle_hvac_licenses.json` is a bundled, offline snapshot of
Seattle's public "Active Business License Tax Certificate" records, filtered
to NAICS code `238220` ("Plumbing, Heating, and Air-Conditioning
Contractors"). It supplements OSM search with real government license
records — covers the whole Puget Sound metro (Seattle, Tacoma, Everett,
Kent, Auburn, and more), not just Seattle proper.

A few things worth knowing:

- **NAICS 238220 mixes plumbing and HVAC** — there's no official code that
  separates them. Every entry is tagged `likelyHvac: true/false` based on
  whether the business/trade name self-identifies as HVAC (heating,
  cooling, furnace, duct, air conditioning); the Search screen shows this
  as "Likely HVAC" vs. "Licensed (Plumbing/HVAC)" per result. Nothing is
  filtered out — a plain plumber with a generic name still shows up, just
  labeled as what it actually is.
- **Phone numbers are from the license registration**, not verified current
  contact info — the Company Detail screen shows this caveat on every
  license-sourced entry.
- **Coverage is limited to this snapshot's area.** Outside the Puget Sound
  metro this source just contributes nothing to a search — OSM search still
  works everywhere.
- **It's entirely offline** — bundled with the app, no network calls, no
  rate limits, unlike the live OSM search.

To refresh this data (e.g. a newer license export): regenerate
`assets/data/seattle_hvac_licenses_raw.json` (name/address/phone/NAICS
filtered from the source CSV, no coordinates), then run the
"Geocode License Data" GitHub Actions workflow (Actions → that workflow →
"Run workflow"). It geocodes every address via Nominatim at its ~1 req/sec
fair-use limit (~15-20 minutes for ~950 rows) and commits the result back
to the branch. It's separate from the release workflow so a data refresh
never blocks a normal APK build.

## Building it yourself

You'll need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
and Android SDK/platform tools (Android Studio is the easiest way to get
both) installed locally — this repo doesn't bundle them.

```bash
flutter pub get
flutter analyze   # optional, should be clean
flutter test      # optional, runs the unit tests
```

### First install (debug build — quickest way to try it)

```bash
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

This works for trying the app out, but a debug-signed build **cannot**
receive in-app updates from CI-built release APKs (Android requires matching
signatures). For real releases, just use CI (see below) — it signs
consistently automatically, no local setup needed.

## Release signing (fully automatic, no setup)

Android only treats an install as an "update" (keeping your data, no
uninstall needed) if it's signed with the same key as what's already
installed. Rather than a human generating a keystore and pasting secrets
into GitHub, `.github/workflows/release.yml` manages this itself: the first
time the workflow ever runs, it generates `android/app/ci-release.keystore`
and commits it straight back into the repo; every run after that finds it
already there and reuses it. Every release from then on is signed
identically, so the in-app updater can install new versions in place.

This means the signing key lives in the repo in plaintext. That's a
deliberate tradeoff for a personal, offline app with no Play Store presence
and no backend — anyone who can read the repo could in principle sign a
lookalike update, which isn't a concern for a private personal tool, but
keep it in mind if this repo's scope ever changes.

## Releasing updates

Shipping a change is:

```bash
git add -A && git commit -m "..."
git tag v1.1.0
git push origin main --tags
```

`.github/workflows/release.yml` picks up the `v*` tag, sets the app version
to match it, builds and signs the APK with the release keystore, and
publishes a GitHub Release with the APK attached. Next time you open the app
(or tap Settings → "Check for updates"), it'll offer to download and install
it — no cable, no Play Store.

Version numbers should be dotted (`v1.1.0`, not `v1.1`) so the in-app
comparison in `lib/utils/version_compare.dart` sorts correctly.

You can also trigger a release without pushing a tag: on GitHub, go to
Actions → "Release APK" → "Run workflow", type a version number, and run it
on any branch. Useful if you'd rather not push tags from wherever you're
working.

## Known limitations

- **OSM coverage varies by area.** It's community-maintained data, so some
  real HVAC companies near you may be missing or mistagged — use "Add
  Company" for anything Search doesn't find.
- **Nominatim/Overpass are shared free services** with fair-use rate limits
  (this app already throttles geocoding to ~1 request/second). Fine for
  personal, occasional searching; not built for heavy automated use.
- **No cloud sync.** All data lives in a local SQLite database on your
  phone. Use Settings → Export periodically as a backup.
