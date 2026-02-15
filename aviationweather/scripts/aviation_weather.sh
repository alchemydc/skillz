#!/usr/bin/env bash
set -euo pipefail

# Aviation Weather API wrapper for OpenClaw
# Queries aviationweather.gov API for METAR, TAF, PIREP, SIGMET, and station info

BASE_URL="https://aviationweather.gov/api/data"
USER_AGENT="OpenClaw-AviationWeather/1.0"

usage() {
  cat >&2 <<EOF
Usage: aviation_weather.sh <subcommand> [args] [flags]

Subcommands:
  metar <IDS>       Current conditions (ICAO codes, comma-separated or @STATE)
  taf <IDS>         Terminal forecasts
  pirep             Pilot reports (requires --bbox)
  sigmet            Active SIGMETs/AIRMETs
  station <IDS>     Station metadata

Flags:
  --format <FMT>    Output format: json (default), raw, decoded
  --hours <N>       Look-back window in hours (default: 2)
  --taf             Include TAF with METAR query
  --bbox <BOX>      Bounding box: lat0,lon0,lat1,lon1
  --raw             Alias for --format raw
  --help            Show this help

Examples:
  aviation_weather.sh metar KDEN
  aviation_weather.sh metar KDEN,KCOS --taf
  aviation_weather.sh taf KASE
  aviation_weather.sh pirep --bbox 38,-106,41,-103
  aviation_weather.sh sigmet
EOF
  exit 1
}

# Check dependencies
if ! command -v curl &>/dev/null; then
  echo "Error: curl is required but not installed." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

# Parse subcommand
if [[ $# -eq 0 ]]; then
  usage
fi

subcommand="$1"
shift

# Parse positional args and flags
ids=""
format="json"
hours="2"
include_taf="false"
bbox=""

case "$subcommand" in
  metar|taf|station)
    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
      ids="$1"
      shift
    fi
    ;;
  pirep|sigmet)
    # No positional args
    ;;
  --help|-h)
    usage
    ;;
  *)
    echo "Error: Unknown subcommand '$subcommand'" >&2
    usage
    ;;
esac

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      format="$2"
      shift 2
      ;;
    --hours)
      hours="$2"
      shift 2
      ;;
    --taf)
      include_taf="true"
      shift
      ;;
    --bbox)
      bbox="$2"
      shift 2
      ;;
    --raw)
      format="raw"
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Error: Unknown flag '$1'" >&2
      usage
      ;;
  esac
done

# Validate required args
case "$subcommand" in
  metar|taf|station)
    if [[ -z "$ids" ]]; then
      echo "Error: $subcommand requires station IDs" >&2
      usage
    fi
    ;;
  pirep)
    if [[ -z "$bbox" ]]; then
      echo "Error: pirep requires --bbox" >&2
      usage
    fi
    ;;
esac

# Build API endpoint and params
endpoint=""
params=""

case "$subcommand" in
  metar)
    endpoint="metar"
    params="ids=${ids}&format=${format}&hours=${hours}"
    if [[ "$include_taf" == "true" ]]; then
      params="${params}&taf=true"
    fi
    if [[ -n "$bbox" ]]; then
      params="${params}&bbox=${bbox}"
    fi
    ;;
  taf)
    endpoint="taf"
    params="ids=${ids}&format=${format}&hours=${hours}"
    if [[ -n "$bbox" ]]; then
      params="${params}&bbox=${bbox}"
    fi
    ;;
  pirep)
    endpoint="pirep"
    params="bbox=${bbox}&format=${format}&hours=${hours}"
    ;;
  sigmet)
    endpoint="airsigmet"
    params="format=${format}&hours=${hours}"
    ;;
  station)
    endpoint="stationinfo"
    params="ids=${ids}&format=${format}"
    if [[ -n "$bbox" ]]; then
      params="${params}&bbox=${bbox}"
    fi
    ;;
esac

# Make API call
url="${BASE_URL}/${endpoint}?${params}"
response=$(curl -sS -A "$USER_AGENT" "$url")

# Check for curl errors
if [[ $? -ne 0 ]]; then
  echo "Error: Failed to fetch data from API" >&2
  exit 1
fi

# If raw format, just output and exit
if [[ "$format" == "raw" ]]; then
  echo "$response"
  exit 0
fi

# Check for empty response
if [[ -z "$response" || "$response" == "[]" || "$response" == "null" ]]; then
  echo "No data available" >&2
  exit 0
fi

# Format JSON output for readability
case "$subcommand" in
  metar)
    echo "$response" | jq -r '.[] | 
      "🌤️  \(.icaoId) — \(.name)  [\(.fltCat // "N/A")]",
      "    Raw:      \(.rawOb)",
      "    Temp:     \(.temp // "N/A")°C  Dewpoint: \(.dewp // "N/A")°C",
      "    Wind:     \(.wdir // "N/A")° at \(.wspd // "N/A") kt",
      "    Vis:      \(.visib // "N/A") SM",
      "    Clouds:   \(if .clouds then (.clouds | map("\(.cover) \(.base) ft") | join(" / ")) else "N/A" end)",
      "    Altimeter: \(.altim // "N/A") hPa",
      ""'
    ;;
  taf)
    echo "$response" | jq -r '.[] |
      "📋 \(.icaoId) — \(.name)",
      "    Raw TAF: \(.rawTAF)",
      "    Valid: \(.validTimeFrom | strftime("%Y-%m-%d %H:%M")) to \(.validTimeTo | strftime("%Y-%m-%d %H:%M"))",
      "    Forecasts:",
      (.fcsts[] | "      \(.timeFrom | strftime("%H:%M"))-\(.timeTo | strftime("%H:%M")): Wind \(.wdir // "VRB")° \(.wspd // 0)kt, Vis \(.visib // "N/A")SM, \(if .clouds then (.clouds | map("\(.cover) \(.base)ft") | join(" ")) else "CLR" end)"),
      ""'
    ;;
  pirep)
    echo "$response" | jq -r '.[] |
      "✈️  PIREP at \(.icaoId // "unknown")",
      "    Aircraft: \(.acType // "N/A")",
      "    Location: \(.lat),\(.lon)",
      "    Altitude: \(.fltLvl // "N/A") (\(.fltLvlType // "N/A"))",
      "    Turbulence: \(.tbInt1 // "none")",
      "    Icing: \(.icgInt1 // "none")",
      "    Raw: \(.rawOb)",
      ""'
    ;;
  sigmet)
    echo "$response" | jq -r '.[] |
      "⚠️  \(.airSigmetType) \(.seriesId) — \(.hazard)",
      "    Valid: \(.validTimeFrom | strftime("%Y-%m-%d %H:%M")) to \(.validTimeTo | strftime("%Y-%m-%d %H:%M"))",
      "    Movement: \(.movementDir // "N/A")° at \(.movementSpd // "N/A") kt",
      "    Altitude: \(.altitudeLow1 // "SFC") to \(.altitudeHi1 // "N/A") ft",
      "    Raw: \(.rawAirSigmet)",
      ""'
    ;;
  station)
    echo "$response" | jq -r '.[] |
      "📍 \(.icaoId) — \(.site)",
      "    IATA: \(.iataId // "N/A")  FAA: \(.faaId // "N/A")  WMO: \(.wmoId // "N/A")",
      "    Location: \(.lat),\(.lon)  Elevation: \(.elev) ft",
      "    State: \(.state // "N/A")  Country: \(.country)",
      "    Products: \(.siteType | join(", "))",
      ""'
    ;;
esac
