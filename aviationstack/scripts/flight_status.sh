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
#
# NOTE – AviationStack API timezone quirk (confirmed 2026-03-06):
#   All datetime fields (scheduled, estimated, actual) contain LOCAL airport
#   times but are stamped with a bogus "+00:00" UTC offset.  The correct IANA
#   timezone is provided separately in .departure.timezone / .arrival.timezone.
#   We strip the misleading offset and use GNU date with TZ= to format correctly.

# fmt_time <iso_timestamp> <iana_timezone>
# Strips the bogus +00:00 offset from AviationStack timestamps and formats
# the local time with the correct timezone abbreviation.
fmt_time() {
  local ts="${1:-}" tz="${2:-UTC}"
  if [[ -z "$ts" || "$ts" == "null" ]]; then
    echo "?"
    return
  fi
  # Strip the bogus UTC offset so GNU date treats the value as local
  ts="${ts%+00:00}"
  ts="${ts%Z}"
  TZ="$tz" date -d "$ts" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || echo "$1"
}

if [[ "$endpoint" == "flights" ]]; then
  echo "$response" | jq -c '.data[]' | while IFS= read -r flight; do
    flight_iata=$(echo "$flight"  | jq -r '.flight.iata // .flight.icao // "?"')
    airline=$(echo "$flight"      | jq -r '.airline.name // "Unknown Airline"')
    status=$(echo "$flight"       | jq -r '.flight_status // "?"')

    dep_airport=$(echo "$flight"  | jq -r '.departure.airport // "?"')
    dep_iata=$(echo "$flight"     | jq -r '.departure.iata // "?"')
    dep_tz=$(echo "$flight"       | jq -r '.departure.timezone // "UTC"')
    dep_terminal=$(echo "$flight" | jq -r '.departure.terminal // empty')
    dep_gate=$(echo "$flight"     | jq -r '.departure.gate // empty')
    dep_delay=$(echo "$flight"    | jq -r '.departure.delay // empty')
    dep_sched=$(echo "$flight"    | jq -r '.departure.scheduled // empty')
    dep_est=$(echo "$flight"      | jq -r '.departure.estimated // empty')
    dep_act=$(echo "$flight"      | jq -r '.departure.actual // empty')

    arr_airport=$(echo "$flight"  | jq -r '.arrival.airport // "?"')
    arr_iata=$(echo "$flight"     | jq -r '.arrival.iata // "?"')
    arr_tz=$(echo "$flight"       | jq -r '.arrival.timezone // "UTC"')
    arr_terminal=$(echo "$flight" | jq -r '.arrival.terminal // empty')
    arr_sched=$(echo "$flight"    | jq -r '.arrival.scheduled // empty')
    arr_est=$(echo "$flight"      | jq -r '.arrival.estimated // empty')
    arr_act=$(echo "$flight"      | jq -r '.arrival.actual // empty')

    dep_sched_fmt=$(fmt_time "$dep_sched" "$dep_tz")
    dep_actual_fmt=$(fmt_time "${dep_act:-$dep_est}" "$dep_tz")
    arr_sched_fmt=$(fmt_time "$arr_sched" "$arr_tz")
    arr_actual_fmt=$(fmt_time "${arr_act:-$arr_est}" "$arr_tz")

    term_str=""
    [[ -n "$dep_terminal" ]] && term_str=" Terminal $dep_terminal"
    [[ -n "$dep_gate" ]]     && term_str="${term_str}, Gate $dep_gate"
    arr_term_str=""
    [[ -n "$arr_terminal" ]] && arr_term_str=" Terminal $arr_terminal"
    delay_str="none"
    [[ -n "$dep_delay" && "$dep_delay" != "null" ]] && delay_str="${dep_delay} min dep"

    printf '✈️  %s (%s)\n' "$flight_iata" "$airline"
    printf '    Status:    %s\n' "$status"
    printf '    From:      %s (%s)%s\n' "$dep_airport" "$dep_iata" "$term_str"
    printf '    To:        %s (%s)%s\n' "$arr_airport" "$arr_iata" "$arr_term_str"
    printf '    Departure: %s (sched) → %s\n' "$dep_sched_fmt" "$dep_actual_fmt"
    printf '    Arrival:   %s (sched) → %s\n' "$arr_sched_fmt" "$arr_actual_fmt"
    printf '    Delay:     %s\n\n' "$delay_str"
  done
elif [[ "$endpoint" == "airports" ]]; then
  echo "$response" | jq -r '.data[] | "🛫 \(.airport_name) (\(.iata_code) / \(.icao_code))\n   Location:  \(.city_iata_code // "Unknown City"), \(.country_name)\n   Timezone:  \(.timezone // "Unknown")\n   Coords:    \(.latitude), \(.longitude)\n"'
elif [[ "$endpoint" == "airlines" ]]; then
  echo "$response" | jq -r '.data[] | "🏢 \(.airline_name) (\(.iata_code) / \(.icao_code))\n   Country:   \(.country_name)\n   Hub:       \(.hub_code // "N/A")\n   Fleet:     \(.fleet_size // "0") aircraft (avg age \(.fleet_average_age // "?") yr)\n   Status:    \(.status)\n   Founded:   \(.date_founded // "?")\n"'
fi
