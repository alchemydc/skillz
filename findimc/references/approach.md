# findIMC Approach

## Data Sources

- Weather areas (primary): `https://aviationweather.gov/api/data/gairmet?hazard=IFR`
- Weather areas (optional supplement): `https://aviationweather.gov/api/data/airsigmet`
- Airport metadata: `https://aviationweather.gov/api/data/stationinfo`
- METAR + flight category: `https://aviationweather.gov/api/data/metar` (`fltCat` field)

## Selection Logic

1. Keep G-AIRMET IFR records (`hazard=IFR`) at selected `--forecast-hour`.
2. Optionally merge SIGMET/AIRMET records when `--source` is `sigmet` or `both`.
3. Intersect each weather-area bbox with the scan bbox.
4. For each selected area, query stations in that bbox and keep airports with ICAO IDs in selected `--countries`.
5. Query METAR JSON directly, keep all checked airports with category from `fltCat`, and mark `MVFR`, `IFR`, `LIFR` as IMC-positive.

## Legacy Signal Logic (SIGMET/AIRMET mode)

- SIGMET hazard text match: `CONVECTIVE`, `THUNDER`, `TS`, `PRECIP`, `RAIN`, `SNOW`, `ICE`, `FZRA`, `SEV`
- SIGMET raw bulletin match: `TSRA`, `+RA`, `SHRA`, `SNOW`, `FZRA`
- AIRMET IFR-focused match: `IFR`, `MT_OBSC`, `CIG`, `VIS`, `BR`, `FG`

## Scope Defaults

- Default scan bbox: `18,-170,72,-52`
- This includes CONUS + Alaska + Hawaii and avoids Europe/Asia.
- Default countries: `US` (override with `--countries`, e.g. `US,CA`).
- Default source mode: `both` with `--forecast-hour 0`.

## Output Modes

- Text mode (default): summary + each area + all checked airports and their categories.
- JSON mode (`--json`): structured `summary` and `areas[].checked_airports[]` payload.
- Debug mode (`--debug`): include full METAR JSON records to verify category and source fields.

## Known Limitations

- G-AIRMET is CONUS-focused and may not cover AK/HI.
- Station metadata can include non-airport sites; filtering uses ICAO + country code list.
- Some stations still return no METAR in the chosen look-back window; fallback airport selection can still include these when needed.
