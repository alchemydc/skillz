# findIMC Approach

## Data Sources

- Weather areas: `https://aviationweather.gov/api/data/airsigmet`
- Airport metadata: `https://aviationweather.gov/api/data/stationinfo`
- METAR + flight category: `https://aviationweather.gov/api/data/metar` (`fltCat` field)

## Selection Logic

1. Keep SIGMET/AIRMET records with coordinates and storm/precip signal:
   - hazard text match: `CONVECTIVE`, `THUNDER`, `TS`, `PRECIP`, `RAIN`, `SNOW`, `ICE`, `FZRA`, `SEV`
   - or raw bulletin match for common precip/storm markers (`TSRA`, `+RA`, `SHRA`, etc.)
2. Intersect each weather-area bbox with the scan bbox.
3. For each selected area, query stations in that bbox and keep airports with ICAO IDs in selected `--countries`.
4. Query METAR JSON directly, keep all checked airports with category from `fltCat`, and mark `MVFR`, `IFR`, `LIFR` as IMC-positive.

## Scope Defaults

- Default scan bbox: `18,-170,72,-52`
- This includes CONUS + Alaska + Hawaii and avoids Europe/Asia.
- Default countries: `US` (override with `--countries`, e.g. `US,CA`).

## Output Modes

- Text mode (default): summary + each area + all checked airports and their categories.
- JSON mode (`--json`): structured `summary` and `areas[].checked_airports[]` payload.
- Debug mode (`--debug`): include full METAR JSON records to verify category and source fields.

## Known Limitations

- SIGMET-focused detection can miss non-SIGMET precip events.
- Station metadata can include non-airport sites; filtering uses ICAO + country code list.
- METAR parsing currently reads formatted aviationweather output blocks.
