---
name: aviationweather
description: >-
  Get aviation weather from aviationweather.gov — METAR observations, TAF
  forecasts, PIREPs, SIGMETs/AIRMETs, and station info. Use when a pilot asks
  about current weather, ceiling, visibility, flight category (VFR/IFR),
  turbulence, icing, or conditions along a route. No API key required.
homepage: https://aviationweather.gov/data/api/
metadata:
  {
    "openclaw":
      {
        "emoji": "🌤️",
        "requires": { "bins": ["curl", "jq"] },
      },
  }
---

# Aviation Weather

Aviation weather observations and forecasts from aviationweather.gov for GA flight planning.

## Quick Start

Current METAR at Denver:
```bash
{baseDir}/scripts/aviation_weather.sh metar KDEN
```

TAF forecast at multiple airports:
```bash
{baseDir}/scripts/aviation_weather.sh taf KDEN,KCOS,KASE
```

METAR + TAF together (route briefing):
```bash
{baseDir}/scripts/aviation_weather.sh metar KDEN,KBJC,KCOS --taf
```

PIREPs in a bounding box (lat0,lon0,lat1,lon1):
```bash
{baseDir}/scripts/aviation_weather.sh pirep --bbox 38,-106,41,-103
```

Active SIGMETs/AIRMETs:
```bash
{baseDir}/scripts/aviation_weather.sh sigmet
```

## Subcommands

| Subcommand | Purpose |
|---|---|
| `metar <IDS>` | Current conditions at station(s). Comma-separated ICAO codes or `@ST` for state. |
| `taf <IDS>` | Terminal forecasts at station(s). |
| `pirep` | Pilot reports. Requires `--bbox`. |
| `sigmet` | Active SIGMETs and AIRMETs. |
| `station <IDS>` | Station metadata (name, coords, elevation, available products). |

## Common Flags

| Flag | Applies to | Default | Description |
|---|---|---|---|
| `--format <FMT>` | all | `json` | Output: `json`, `raw`, `decoded` |
| `--hours <N>` | metar, taf, pirep, sigmet | 2 | Look-back window in hours |
| `--taf` | metar | off | Include TAF with METAR query |
| `--bbox <lat0,lon0,lat1,lon1>` | metar, taf, pirep | — | Area search by bounding box |
| `--raw` | all | — | Alias for `--format raw` (standard METAR/TAF text) |

## Direct API Access

Quick curl one-liner for JSON:
```bash
curl -s "https://aviationweather.gov/api/data/metar?ids=KDEN&format=json" | jq '.'
```

Raw METAR text:
```bash
curl -s "https://aviationweather.gov/api/data/metar?ids=KDEN&format=raw"
```

> [!NOTE]
> For full API parameter and response details, see [api_reference.md](references/api_reference.md).

## Flight Category Reference

| Category | Ceiling | Visibility |
|---|---|---|
| VFR | > 3,000 ft AGL | > 5 SM |
| MVFR | 1,000–3,000 ft | 3–5 SM |
| IFR | 500–999 ft | 1–2 SM |
| LIFR | < 500 ft | < 1 SM |
