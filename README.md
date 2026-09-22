# HVAC Leads

A personal, on-device CRM for tracking HVAC job applications. It searches
OpenStreetMap for HVAC companies within a radius of your home, lets you save
contact info and notes, and tracks where each application stands — all
stored locally on your phone, no account or backend required.

## How it works

- **Search** — set your home address once (Settings), pick a radius, and tap
  "Search Nearby." The app queries the free OpenStreetMap Overpass API for
  HVAC-tagged businesses and businesses whose name mentions
  HVAC/heating/cooling, and plots them on a map and a list.
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
               OverpassService, EnrichmentService, ExportService,
               UpdateService (GitHub Releases)
  screens/     Search/Map, Company List, Company Detail, Add Manual Company,
               Export, Settings
  widgets/     UpdateBanner (startup update check)
  utils/       distance.dart (haversine), version_compare.dart
test/          Unit tests for the above (no device/emulator needed)
.github/workflows/release.yml   Builds + signs + publishes a release APK
```

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
signatures — see below). For the real workflow, do the one-time release
signing setup first, then install a release build from the start.

## One-time setup: release signing (required for in-app updates)

Android only treats an install as an "update" (keeping your data, no
uninstall needed) if it's signed with the same key as what's already
installed. So there's one release keystore, used both by CI and for your
very first manual install.

1. **Generate a keystore** (do this once, keep the file and passwords safe —
   losing it means future updates can never install over the app again):
   ```bash
   keytool -genkey -v -keystore release.keystore -alias hvacleads \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. **Add it to GitHub** so CI can sign release builds: Repo → Settings →
   Secrets and variables → Actions → New repository secret, four times:
   - `RELEASE_KEYSTORE_BASE64` — output of `base64 -w0 release.keystore`
     (macOS: `openssl base64 -A -in release.keystore`)
   - `RELEASE_KEYSTORE_PASSWORD`
   - `RELEASE_KEY_ALIAS` — `hvacleads` if you used the command above
   - `RELEASE_KEY_PASSWORD`
3. **Build your first install with the same keystore.** Create
   `android/key.properties` (already gitignored) pointing at it:
   ```properties
   storeFile=/absolute/path/to/release.keystore
   storePassword=...
   keyAlias=hvacleads
   keyPassword=...
   ```
   Then:
   ```bash
   flutter build apk --release
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```
   (Or copy `app-release.apk` to your phone and open it — Android will
   prompt you to allow "Install unknown apps" for whichever app you opened
   it with, e.g. Files or Chrome. Allow it once.)

From here on, every CI-built release will match this signature and install
as a seamless update.

## Releasing updates

Once the one-time setup above is done, shipping a change is:

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
