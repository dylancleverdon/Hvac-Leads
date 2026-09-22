#!/usr/bin/env python3
"""Geocodes assets/data/seattle_hvac_licenses_raw.json via Nominatim and
writes assets/data/seattle_hvac_licenses.json with lat/lng added.

Run manually (via the "Geocode License Data" GitHub Actions workflow, or
locally) whenever the source license CSV is refreshed and
seattle_hvac_licenses_raw.json is regenerated. Throttled to Nominatim's
~1 request/second fair-use limit, same convention as
lib/services/geocoding_service.dart.
"""

import json
import sys
import time
import urllib.parse
import urllib.request

RAW_PATH = "assets/data/seattle_hvac_licenses_raw.json"
OUT_PATH = "assets/data/seattle_hvac_licenses.json"
USER_AGENT = "HvacLeads/1.0 (personal job-hunt tracker app, one-time data geocode)"
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"


def geocode(address: str):
    query = urllib.parse.urlencode({"q": address, "format": "json", "limit": "1"})
    req = urllib.request.Request(
        f"{NOMINATIM_URL}?{query}", headers={"User-Agent": USER_AGENT}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        results = json.load(resp)
    if not results:
        return None
    return float(results[0]["lat"]), float(results[0]["lon"])


def main():
    with open(RAW_PATH, encoding="utf-8") as f:
        rows = json.load(f)

    out = []
    failures = []
    for i, row in enumerate(rows):
        try:
            coords = geocode(row["address"])
        except Exception as e:  # noqa: BLE001 - log and continue
            coords = None
            failures.append((row["address"], str(e)))

        if coords is None:
            failures.append((row["address"], "no match"))
        else:
            lat, lng = coords
            out.append({**row, "lat": lat, "lng": lng})

        if (i + 1) % 25 == 0 or i == len(rows) - 1:
            print(f"geocoded {i + 1}/{len(rows)} ({len(out)} succeeded)", file=sys.stderr)

        time.sleep(1.0)  # respect Nominatim's ~1 req/sec fair-use limit

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    print(f"Wrote {len(out)}/{len(rows)} geocoded rows to {OUT_PATH}")
    if failures:
        print(f"{len(failures)} addresses failed to geocode:")
        for addr, reason in failures[:25]:
            print(f"  - {addr}: {reason}")
        if len(failures) > 25:
            print(f"  ... and {len(failures) - 25} more")


if __name__ == "__main__":
    main()
