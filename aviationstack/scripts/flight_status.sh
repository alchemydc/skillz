#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  flight_status.sh <subcommand> [args] [flags]

Subcommands:
  flight <IATA>       Look up specific flight (e.g. AA100)
  route <DEP> <ARR>   Look up flights between airports (e.g. JFK LAX)
  airport <IATA>     Look up airport details (e.g. JFK)
  airline <IATA>     Look up airline details (e.g. AA)
  active              List currently airborne flights

Flags:
  --raw               Output raw JSON

Note: Free plan supports basic flight lookup only.
      Advanced filters require an upgraded AviationStack plan.
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then usage; fi

# Check Dependencies
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: 'jq' is not installed." >&2
  exit 1
fi

if [[ -z "${AVIATIONSTACK_API_KEY:-}" ]]; then
  echo "Error: AVIATIONSTACK_API_KEY environment variable is not set." >&2
  exit 1
fi

cmd="$1"
shift

endpoint="flights"
params=""
raw=0

# Parse Subcommand Args
case "$cmd" in
  flight)
    if [[ $# -lt 1 ]]; then usage; fi
    params="&flight_iata=$1"
    shift
    ;;
  route|airport|airline|active)
    echo "Error: '$cmd' subcommand requires a paid AviationStack plan. This skill uses the free tier which only supports 'flight' lookups." >&2
    exit 1
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: $cmd" >&2
    usage
    ;;
esac

# Parse Flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw)
      raw=1
      shift
      ;;
    --status|--date|--limit|--dep|--arr)
      echo "Error: '$1' requires a paid AviationStack plan. This skill uses the free tier which only supports basic flight lookup." >&2
      exit 1
      ;;
    *)
      echo "Unknown flag: $1" >&2
      usage
      ;;
  esac
done

BASE_URL="https://api.aviationstack.com/v1"
url="${BASE_URL}/${endpoint}?access_key=${AVIATIONSTACK_API_KEY}${params}"

response=$(curl -sS "$url")

# Check for API Errors
error=$(echo "$response" | jq -r '.error.message // empty')
if [[ -n "$error" ]]; then
  echo "API Error: $error" >&2
  exit 1
fi

if [[ "$raw" -eq 1 ]]; then
  echo "$response"
  exit 0
fi

# Check for empty results
count=$(echo "$response" | jq '.data | if type == "array" then length else 0 end')
if [[ "$count" -eq 0 ]]; then
  echo "No results found." >&2
  exit 0
fi

# Formatted Output
if [[ "$endpoint" == "flights" ]]; then
  echo "$response" | jq -r '.data[] | "✈️  \(.flight.iata // .flight.icao // "Unknown") (\(.airline.name // "Unknown Airline"))\n    Status:    \(.flight_status)\n    From:      \(.departure.airport // "Unknown") (\(.departure.iata // "?"))\(if .departure.terminal then " Terminal \(.departure.terminal)" else "" end)\(if .departure.gate then ", Gate \(.departure.gate)" else "" end)\n    To:        \(.arrival.airport // "Unknown") (\(.arrival.iata // "?"))\(if .arrival.terminal then " Terminal \(.arrival.terminal)" else "" end)\n    Departure: \(.departure.scheduled // "?") (sched) → \(.departure.actual // .departure.estimated // "?")\n    Arrival:   \(.arrival.scheduled // "?") (sched) → \(.arrival.actual // .arrival.estimated // "?")\n    Delay:     \(if .departure.delay then "\(.departure.delay) min dep" else "none" end)\n"'
elif [[ "$endpoint" == "airports" ]]; then
  echo "$response" | jq -r '.data[] | "🛫 \(.airport_name) (\(.iata_code) / \(.icao_code))\n   Location:  \(.city_iata_code // "Unknown City"), \(.country_name)\n   Timezone:  \(.timezone // "Unknown")\n   Coords:    \(.latitude), \(.longitude)\n"'
elif [[ "$endpoint" == "airlines" ]]; then
  echo "$response" | jq -r '.data[] | "🏢 \(.airline_name) (\(.iata_code) / \(.icao_code))\n   Country:   \(.country_name)\n   Hub:       \(.hub_code // "N/A")\n   Fleet:     \(.fleet_size // "0") aircraft (avg age \(.fleet_average_age // "?") yr)\n   Status:    \(.status)\n   Founded:   \(.date_founded // "?")\n"'
fi
