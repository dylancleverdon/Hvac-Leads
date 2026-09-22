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
import re
import sys
import time
import urllib.parse
import urllib.request

RAW_PATH = "assets/data/seattle_hvac_licenses_raw.json"
OUT_PATH = "assets/data/seattle_hvac_licenses.json"
USER_AGENT = "HvacLeads/1.0 (personal job-hunt tracker app, one-time data geocode)"
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"

# Suite/unit designators ("# STE A", "#101", "UNIT 5", ...) frequently make
# Nominatim's address parser fail to match anything at all, even though the
# base street address is fine — a business unit within a building shares
# the building's coordinates anyway, so stripping this for the geocoding
# query (not for the stored/displayed address) is a safe fallback. Matches
# from the first "#" or whole-word unit keyword to the end of the street
# segment (not just one token — "# STE 101" needs both "STE" and "101"
# gone). Keywords need \b on both sides so e.g. "FL" doesn't match inside
# "FLEET RD".
_UNIT_START = re.compile(
    r"\s*(?:#|\b(?:STE|SUITE|UNIT|APT|BLDG|BUILDING)\b).*$",
    re.IGNORECASE,
)


def strip_unit(address: str) -> str:
    street, _, rest = address.partition(",")
    stripped_street = _UNIT_START.sub("", street).strip()
    return f"{stripped_street},{rest}" if rest else stripped_street


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
        address = row["address"]
        coords = None
        last_error = None

        try:
            coords = geocode(address)
        except Exception as e:  # noqa: BLE001 - log and continue
            last_error = str(e)
        time.sleep(1.0)  # respect Nominatim's ~1 req/sec fair-use limit

        if coords is None:
            stripped = strip_unit(address)
            if stripped and stripped != address:
                try:
                    coords = geocode(stripped)
                except Exception as e:  # noqa: BLE001
                    last_error = str(e)
                time.sleep(1.0)

        if coords is None:
            failures.append((address, last_error or "no match"))
        else:
            lat, lng = coords
            out.append({**row, "lat": lat, "lng": lng})

        if (i + 1) % 25 == 0 or i == len(rows) - 1:
            print(f"geocoded {i + 1}/{len(rows)} ({len(out)} succeeded)", file=sys.stderr)

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
