# Aviation Weather API Reference

Quick reference for the aviationweather.gov API endpoints used by this skill.

## Base Information

- **Base URL**: `https://aviationweather.gov/api/data`
- **Authentication**: None required
- **Rate Limit**: 100 requests/minute
- **User-Agent**: Set to `OpenClaw-AviationWeather/1.0` to avoid automated filtering

## Output Formats

Most endpoints support multiple formats via the `format` query parameter:

- `json` — Structured JSON (default, recommended)
- `raw` — Standard METAR/TAF text format
- `decoded` — Human-readable decoded text
- `xml` — XML format
- `geojson` — GeoJSON (for mapping applications)

## Endpoints

### METAR — Terminal Observations

**Endpoint**: `/api/data/metar`

**Parameters**:
- `ids` (required) — ICAO station codes, comma-separated (e.g., `KDEN,KCOS`) or state shorthand (`@CO`)
- `format` — Output format (default: `json`)
- `hours` — Look-back window in hours (default: 2, max: 15 days)
- `taf` — Boolean, include TAF with METAR (default: `false`)
- `bbox` — Bounding box: `lat0,lon0,lat1,lon1` (SW corner, NE corner)

**Key JSON Fields**:
- `icaoId` — Station ICAO code
- `name` — Station name and location
- `reportTime` — Observation time (ISO 8601)
- `temp` — Temperature (°C)
- `dewp` — Dewpoint (°C)
- `wdir` — Wind direction (degrees)
- `wspd` — Wind speed (knots)
- `visib` — Visibility (statute miles, `10+` for ≥10 SM)
- `altim` — Altimeter setting (hPa)
- `fltCat` — Flight category: `VFR`, `MVFR`, `IFR`, `LIFR`
- `clouds[]` — Array of cloud layers with `cover` (SKC/FEW/SCT/BKN/OVC) and `base` (feet AGL)
- `rawOb` — Raw METAR text

### TAF — Terminal Forecasts

**Endpoint**: `/api/data/taf`

**Parameters**:
- `ids` (required) — ICAO station codes
- `format` — Output format
- `hours` — Look-back window
- `bbox` — Bounding box

**Key JSON Fields**:
- `icaoId` — Station ICAO code
- `name` — Station name
- `issueTime` — TAF issue time
- `validTimeFrom` / `validTimeTo` — Forecast valid period (Unix timestamps)
- `rawTAF` — Raw TAF text
- `fcsts[]` — Array of forecast periods, each with:
  - `timeFrom` / `timeTo` — Period start/end (Unix timestamps)
  - `fcstChange` — Change indicator: `FM` (from), `BECMG`, `TEMPO`, `PROB`
  - `wdir` / `wspd` — Wind direction/speed
  - `visib` — Visibility
  - `clouds[]` — Cloud layers
  - `wxString` — Weather phenomena (e.g., `-RA`, `TSRA`)

### PIREP — Pilot Reports

**Endpoint**: `/api/data/pirep`

**Parameters**:
- `bbox` (required) — Bounding box
- `format` — Output format
- `hours` — Look-back window

**Key JSON Fields**:
- `icaoId` — Nearest station
- `obsTime` — Report time (Unix timestamp)
- `acType` — Aircraft type
- `lat` / `lon` — Location
- `fltLvl` — Flight level
- `tbInt1` — Turbulence intensity: `NEG`, `LGT`, `MOD`, `SEV`, `EXTRM`
- `icgInt1` — Icing intensity (same scale)
- `rawOb` — Raw PIREP text

### SIGMET/AIRMET — Significant Meteorological Information

**Endpoint**: `/api/data/airsigmet`

**Parameters**:
- `format` — Output format
- `hours` — Look-back window (default: 6)

**Key JSON Fields**:
- `airSigmetType` — `SIGMET` or `AIRMET`
- `hazard` — Hazard type: `CONVECTIVE`, `TURB`, `ICE`, `IFR`, `MTN_OBSCN`, etc.
- `validTimeFrom` / `validTimeTo` — Valid period
- `movementDir` / `movementSpd` — Movement direction/speed
- `altitudeLow1` / `altitudeHi1` — Altitude range (feet)
- `coords[]` — Array of lat/lon points defining the area
- `rawAirSigmet` — Raw SIGMET/AIRMET text

### Station Info — Station Metadata

**Endpoint**: `/api/data/stationinfo`

**Parameters**:
- `ids` (required) — ICAO station codes
- `format` — Output format
- `bbox` — Bounding box

**Key JSON Fields**:
- `icaoId` — ICAO code
- `iataId` — IATA code (3-letter)
- `faaId` — FAA identifier
- `site` — Station name
- `lat` / `lon` — Coordinates
- `elev` — Elevation (feet MSL)
- `state` / `country` — Location
- `siteType[]` — Available products: `METAR`, `TAF`, etc.

## Station ID Patterns

- **Single station**: `KDEN`
- **Multiple stations**: `KDEN,KCOS,KASE` (comma-separated, no spaces)
- **State shorthand**: `@CO` (all stations in Colorado)
- **Bounding box**: `bbox=38,-106,41,-103` (SW lat, SW lon, NE lat, NE lon)

## Error Handling

- **Empty results**: API returns `[]` (empty JSON array) with HTTP 200
- **Invalid station**: Returns empty array, not an error
- **Rate limit exceeded**: HTTP 429 (Too Many Requests)
- **Malformed request**: HTTP 400 (Bad Request)

## Flight Category Definitions

| Category | Ceiling | Visibility |
|---|---|---|
| VFR | > 3,000 ft AGL | > 5 SM |
| MVFR | 1,000–3,000 ft | 3–5 SM |
| IFR | 500–999 ft | 1–2 SM |
| LIFR | < 500 ft | < 1 SM |

## Example Queries

```bash
# METAR for Denver
curl -s "https://aviationweather.gov/api/data/metar?ids=KDEN&format=json"

# TAF for multiple stations
curl -s "https://aviationweather.gov/api/data/taf?ids=KDEN,KCOS&format=json"

# PIREPs in Colorado Front Range
curl -s "https://aviationweather.gov/api/data/pirep?bbox=38,-106,41,-103&format=json"

# Active SIGMETs
curl -s "https://aviationweather.gov/api/data/airsigmet?format=json&hours=6"

# Station info
curl -s "https://aviationweather.gov/api/data/stationinfo?ids=KDEN&format=json"
```
