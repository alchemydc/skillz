---
name: findimc
description: >-
  Find active storm/precip weather areas, pick nearby airports by country, and
  report airports currently in MVFR, IFR, or LIFR using AviationWeather data
  and METAR flight categories. Use when a pilot asks where IMC is currently
  being reported around significant weather.
metadata:
  {
    "openclaw":
      {
        "emoji": "IMC",
        "requires": { "bins": ["curl", "jq", "bash"] },
      },
  }
---

# findIMC

Identify significant storm/precip weather areas and return airports currently reporting IMC-like categories (MVFR/IFR/LIFR).

## Quick Start

Run with default North America scope (includes CONUS, AK, HI):
```bash
bash {baseDir}/scripts/find_imc.sh
```

Increase scan depth:
```bash
bash {baseDir}/scripts/find_imc.sh --hours 6 --max-areas 8 --airports-per-area 6
```

Set explicit search extent:
```bash
bash {baseDir}/scripts/find_imc.sh --search-bbox 18,-170,72,-52
```

## How It Works

1. Pull active SIGMET/AIRMET products and keep weather-significant storm/precip areas.
2. Convert each area polygon into a bounding box and select a handful of airports in selected countries.
3. Query METAR via `aviation_weather.sh`, then report all checked airports with category and highlight `MVFR`, `IFR`, or `LIFR`.

## Flags

- `--hours <N>`: look-back hours for weather-area scan (default `4`)
- `--search-bbox <lat0,lon0,lat1,lon1>`: region to scan (default `18,-170,72,-52`)
- `--countries <C1,C2,...>`: airport country filter using ISO alpha-2 codes (default `US`)
- `--max-areas <N>`: max weather areas to evaluate (default `5`)
- `--airports-per-area <N>`: airport sample size for each area (default `5`)
- `--metar-hours <N>`: METAR look-back hours (default `2`)
- `--json`: emit structured JSON output
- `--debug`: include full METAR JSON records for checked airports
- `--debug-airport <ICAO>`: only print debug METAR JSON for one airport code

## Notes

- Default bbox includes AK/HI and excludes Europe/Asia.
- Airports are filtered by `--countries` (default `US`) in station metadata.
- Flight category (`VFR/MVFR/IFR/LIFR`) comes directly from METAR `fltCat` in AviationWeather API JSON.
- Significant precip/storm detection uses SIGMET hazard text and bulletin text heuristics.
