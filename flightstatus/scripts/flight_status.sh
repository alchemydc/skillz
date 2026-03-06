#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# flight_status.sh — Flight tracking via FlightAware AeroAPI (primary)
#                     with AviationStack as fallback.
#
# Env vars:
#   FLIGHTAWARE_API_KEY    — FlightAware AeroAPI key (primary, recommended)
#   AVIATIONSTACK_API_KEY  — AviationStack key (fallback)
#
# At least one of the above must be set.
###############################################################################

AEROAPI_BASE="https://aeroapi.flightaware.com/aeroapi"
AVSTACK_BASE="https://api.aviationstack.com/v1"

usage() {
  cat >&2 <<'EOF'
Usage:
  flight_status.sh <subcommand> [args] [flags]

Subcommands:
  flight <IDENT>         Look up a specific flight (e.g. AA100, UAL100, N12345)
  airport <CODE>         Airport info and current delays (e.g. JFK, KJFK)
  departures <CODE>      Recent/upcoming departures from an airport
  arrivals <CODE>        Recent/upcoming arrivals at an airport
  route <ORIG> <DEST>    Flights between two airports (e.g. JFK LAX)

Flags:
  --raw                  Output raw JSON response
  --fallback             Force use of AviationStack (skip FlightAware)

Data source:
  Primary:  FlightAware AeroAPI (requires FLIGHTAWARE_API_KEY)
  Fallback: AviationStack free tier (requires AVIATIONSTACK_API_KEY)
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then usage; fi

# Handle help before anything else
if [[ "$1" == "-h" || "$1" == "--help" ]]; then usage; fi

# Check dependencies
for dep in curl jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Error: '$dep' is not installed." >&2
    exit 1
  fi
done

# Must have at least one API key
if [[ -z "${FLIGHTAWARE_API_KEY:-}" && -z "${AVIATIONSTACK_API_KEY:-}" ]]; then
  echo "Error: Set FLIGHTAWARE_API_KEY (preferred) or AVIATIONSTACK_API_KEY." >&2
  exit 1
fi

cmd="$1"
shift

raw=0
force_fallback=0
ident=""
airport_code=""
orig_code=""
dest_code=""

# Parse subcommand args
case "$cmd" in
  flight)
    [[ $# -lt 1 ]] && usage
    ident="$1"; shift
    ;;
  airport)
    [[ $# -lt 1 ]] && usage
    airport_code="$1"; shift
    ;;
  departures)
    [[ $# -lt 1 ]] && usage
    airport_code="$1"; shift
    ;;
  arrivals)
    [[ $# -lt 1 ]] && usage
    airport_code="$1"; shift
    ;;
  route)
    [[ $# -lt 2 ]] && usage
    orig_code="$1"; shift
    dest_code="$1"; shift
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: $cmd" >&2
    usage
    ;;
esac

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw)       raw=1; shift ;;
    --fallback)  force_fallback=1; shift ;;
    *)           echo "Unknown flag: $1" >&2; usage ;;
  esac
done

###############################################################################
# IATA → ICAO ident conversion for FlightAware
#
# FlightAware strongly prefers ICAO idents (e.g. "UAL100" not "UA100").
# Common 2-letter IATA codes get auto-prefixed with ICAO airline code.
# If the ident is already 3-letter ICAO-style or a registration, pass through.
###############################################################################
iata_to_icao_ident() {
  local id="$1"
  # If it starts with N and is a registration (e.g. N12345), pass through
  if [[ "$id" =~ ^N[0-9] ]]; then
    echo "$id"
    return
  fi
  # If it's already 3+ alpha prefix (ICAO style like UAL100), pass through
  if [[ "$id" =~ ^[A-Za-z]{3}[0-9] ]]; then
    echo "$id"
    return
  fi
  # Try to convert 2-letter IATA airline prefix to ICAO
  # Common airline mappings (extend as needed)
  local prefix="${id%%[0-9]*}"
  local num="${id#"$prefix"}"
  prefix="${prefix^^}"  # uppercase

  declare -A iata_to_icao=(
    [AA]=AAL [UA]=UAL [DL]=DAL [WN]=SWA [AS]=ASA [B6]=JBU
    [NK]=NKS [F9]=FFT [HA]=HAL [SY]=SCX [G4]=AAY [QX]=QXE
    [OH]=COM [MQ]=ENY [OO]=SKW [YX]=RPA [9E]=EDV [CP]=CPZ
    [BA]=BAW [LH]=DLH [AF]=AFR [KL]=KLM [EK]=UAE [QR]=QTR
    [SQ]=SIA [CX]=CPA [NH]=ANA [JL]=JAL [QF]=QFA [AC]=ACA
    [WS]=WJA [AM]=AMX [AV]=AVA [CM]=CMP [LA]=LAN [IB]=IBE
    [LX]=SWR [OS]=AUA [SK]=SAS [AY]=FIN [TK]=THY [EI]=EIN
    [VS]=VIR [TP]=TAP [AZ]=ITY [LO]=LOT [RO]=ROT [SU]=AFL
    [ET]=ETH [SA]=SAA [MS]=MSR [RJ]=RJA [GF]=GFA [WY]=OMA
    [PK]=PIA [AI]=AIC [9W]=JAI [SV]=SVA [KE]=KAL [OZ]=AAR
    [CI]=CAL [BR]=EVA [CZ]=CSN [MU]=CES [CA]=CCA [HU]=CHH
    [ZH]=CSZ [3U]=CSC [FM]=CSH [MF]=CXA [SC]=CDG
  )

  if [[ -n "${iata_to_icao[$prefix]:-}" ]]; then
    echo "${iata_to_icao[$prefix]}${num}"
  else
    # Can't convert — pass as-is and let API try
    echo "$id"
  fi
}

###############################################################################
# FlightAware AeroAPI helpers
###############################################################################
fa_curl() {
  local endpoint="$1"
  curl -sS -H "x-apikey: ${FLIGHTAWARE_API_KEY}" "${AEROAPI_BASE}${endpoint}"
}

fa_available() {
  [[ -n "${FLIGHTAWARE_API_KEY:-}" && "$force_fallback" -eq 0 ]]
}

###############################################################################
# AviationStack (fallback) helpers
###############################################################################
as_curl() {
  local endpoint="$1" params="$2"
  curl -sS "${AVSTACK_BASE}/${endpoint}?access_key=${AVIATIONSTACK_API_KEY}${params}"
}

as_available() {
  [[ -n "${AVIATIONSTACK_API_KEY:-}" ]]
}

###############################################################################
# Time formatting helper
###############################################################################
fmt_time() {
  local ts="${1:-}" tz="${2:-UTC}"
  if [[ -z "$ts" || "$ts" == "null" ]]; then
    echo "?"
    return
  fi
  TZ="$tz" date -d "$ts" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || echo "$ts"
}

# Like fmt_time but for AviationStack bogus-offset timestamps
fmt_time_as() {
  local ts="${1:-}" tz="${2:-UTC}"
  if [[ -z "$ts" || "$ts" == "null" ]]; then
    echo "?"
    return
  fi
  ts="${ts%+00:00}"
  ts="${ts%Z}"
  TZ="$tz" date -d "$ts" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || echo "$1"
}

###############################################################################
# Compute delay in minutes between two ISO timestamps
###############################################################################
compute_delay_min() {
  local sched="$1" actual="$2"
  if [[ -z "$sched" || "$sched" == "null" || -z "$actual" || "$actual" == "null" ]]; then
    echo ""
    return
  fi
  local s_epoch a_epoch
  s_epoch=$(date -d "$sched" +%s 2>/dev/null) || { echo ""; return; }
  a_epoch=$(date -d "$actual" +%s 2>/dev/null) || { echo ""; return; }
  local diff=$(( (a_epoch - s_epoch) / 60 ))
  if [[ $diff -gt 0 ]]; then
    echo "$diff"
  else
    echo ""
  fi
}

###############################################################################
# FlightAware: flight status
###############################################################################
fa_flight() {
  local ident="$1"
  local icao_ident
  icao_ident=$(iata_to_icao_ident "$ident")

  local response
  response=$(fa_curl "/flights/${icao_ident}?ident_type=designator&max_pages=1")

  # Check for errors
  local err
  err=$(echo "$response" | jq -r '.title // .error // empty' 2>/dev/null)
  if [[ -n "$err" ]]; then
    echo "FlightAware API error: $err" >&2
    return 1
  fi

  local count
  count=$(echo "$response" | jq '.flights | if type == "array" then length else 0 end' 2>/dev/null)
  if [[ "${count:-0}" -eq 0 ]]; then
    echo "No flights found for '$ident' via FlightAware." >&2
    return 1
  fi

  if [[ "$raw" -eq 1 ]]; then
    echo "$response"
    return 0
  fi

  # Display each flight (usually shows recent + upcoming)
  echo "$response" | jq -c '.flights[]' | while IFS= read -r flight; do
    local fl_ident fl_iata fl_icao operator status
    fl_ident=$(echo "$flight" | jq -r '.ident // "?"')
    fl_iata=$(echo "$flight"  | jq -r '.ident_iata // empty')
    fl_icao=$(echo "$flight"  | jq -r '.ident_icao // empty')
    operator=$(echo "$flight" | jq -r '.operator // "?"')

    local cancelled diverted
    cancelled=$(echo "$flight" | jq -r '.cancelled // false')
    diverted=$(echo "$flight"  | jq -r '.diverted // false')

    # Derive status from OOOI times
    local sched_out est_out actual_out actual_off
    local sched_in est_in actual_in actual_on
    sched_out=$(echo "$flight" | jq -r '.scheduled_out // empty')
    est_out=$(echo "$flight"   | jq -r '.estimated_out // empty')
    actual_out=$(echo "$flight" | jq -r '.actual_out // empty')
    actual_off=$(echo "$flight" | jq -r '.actual_off // empty')
    sched_in=$(echo "$flight"  | jq -r '.scheduled_in // empty')
    est_in=$(echo "$flight"    | jq -r '.estimated_in // empty')
    actual_in=$(echo "$flight" | jq -r '.actual_in // empty')
    actual_on=$(echo "$flight" | jq -r '.actual_on // empty')

    local status_str=""
    if [[ "$cancelled" == "true" ]]; then
      status_str="Cancelled"
    elif [[ "$diverted" == "true" ]]; then
      status_str="Diverted"
    elif [[ -n "$actual_in" && "$actual_in" != "null" ]]; then
      status_str="Arrived"
    elif [[ -n "$actual_on" && "$actual_on" != "null" ]]; then
      status_str="Landed"
    elif [[ -n "$actual_off" && "$actual_off" != "null" ]]; then
      status_str="En Route"
    elif [[ -n "$actual_out" && "$actual_out" != "null" ]]; then
      status_str="Taxiing Out"
    else
      status_str="Scheduled"
    fi

    # Also grab the text status from FA if available
    local fa_status
    fa_status=$(echo "$flight" | jq -r '.status // empty')
    if [[ -n "$fa_status" ]]; then
      status_str="$fa_status"
    fi

    # Origin / Destination
    local orig_name orig_code orig_tz dest_name dest_code dest_tz
    orig_name=$(echo "$flight" | jq -r '.origin.name // "?"')
    orig_code=$(echo "$flight" | jq -r '.origin.code_iata // .origin.code // "?"')
    orig_tz=$(echo "$flight"   | jq -r '.origin.timezone // "UTC"')
    dest_name=$(echo "$flight" | jq -r '.destination.name // "?"')
    dest_code=$(echo "$flight" | jq -r '.destination.code_iata // .destination.code // "?"')
    dest_tz=$(echo "$flight"   | jq -r '.destination.timezone // "UTC"')

    # Gate / terminal
    local gate_orig gate_dest term_orig term_dest baggage
    gate_orig=$(echo "$flight" | jq -r '.gate_origin // empty')
    gate_dest=$(echo "$flight" | jq -r '.gate_destination // empty')
    term_orig=$(echo "$flight" | jq -r '.terminal_origin // empty')
    term_dest=$(echo "$flight" | jq -r '.terminal_destination // empty')
    baggage=$(echo "$flight"   | jq -r '.baggage_claim // empty')

    # Aircraft
    local registration aircraft_type
    registration=$(echo "$flight"  | jq -r '.registration // empty')
    aircraft_type=$(echo "$flight" | jq -r '.aircraft_type // empty')

    # Compute delays
    local dep_delay arr_delay
    dep_delay=$(compute_delay_min "${sched_out:-}" "${est_out:-${actual_out:-}}")
    arr_delay=$(compute_delay_min "${sched_in:-}" "${est_in:-${actual_in:-}}")

    # Best departure/arrival times to display
    local dep_best arr_best
    dep_best="${actual_out:-${est_out:-${sched_out:-}}}"
    arr_best="${actual_in:-${est_in:-${sched_in:-}}}"

    local dep_sched_fmt dep_best_fmt arr_sched_fmt arr_best_fmt
    dep_sched_fmt=$(fmt_time "$sched_out" "$orig_tz")
    dep_best_fmt=$(fmt_time "$dep_best" "$orig_tz")
    arr_sched_fmt=$(fmt_time "$sched_in" "$dest_tz")
    arr_best_fmt=$(fmt_time "$arr_best" "$dest_tz")

    # Build display strings
    local ident_display="$fl_ident"
    [[ -n "$fl_iata" ]] && ident_display="${fl_iata} / ${fl_icao:-$fl_ident}"

    local orig_detail="" dest_detail=""
    [[ -n "$term_orig" ]] && orig_detail=" Terminal $term_orig"
    [[ -n "$gate_orig" ]] && orig_detail="${orig_detail}, Gate $gate_orig"
    [[ -n "$term_dest" ]] && dest_detail=" Terminal $term_dest"
    [[ -n "$gate_dest" ]] && dest_detail="${dest_detail}, Gate $gate_dest"
    [[ -n "$baggage" ]]   && dest_detail="${dest_detail}, Baggage $baggage"

    local delay_str="none"
    if [[ -n "$dep_delay" && -n "$arr_delay" ]]; then
      delay_str="${dep_delay} min dep / ${arr_delay} min arr"
    elif [[ -n "$dep_delay" ]]; then
      delay_str="${dep_delay} min dep"
    elif [[ -n "$arr_delay" ]]; then
      delay_str="${arr_delay} min arr"
    fi

    local aircraft_str=""
    [[ -n "$aircraft_type" ]] && aircraft_str="$aircraft_type"
    [[ -n "$registration" ]] && aircraft_str="${aircraft_str:+$aircraft_str / }$registration"

    printf '✈️  %s (%s)\n' "$ident_display" "$operator"
    printf '    Status:    %s\n' "$status_str"
    printf '    From:      %s (%s)%s\n' "$orig_name" "$orig_code" "$orig_detail"
    printf '    To:        %s (%s)%s\n' "$dest_name" "$dest_code" "$dest_detail"
    printf '    Departure: %s (sched) → %s\n' "$dep_sched_fmt" "$dep_best_fmt"
    printf '    Arrival:   %s (sched) → %s\n' "$arr_sched_fmt" "$arr_best_fmt"
    printf '    Delay:     %s\n' "$delay_str"
    [[ -n "$aircraft_str" ]] && printf '    Aircraft:  %s\n' "$aircraft_str"
    printf '    Source:    FlightAware\n\n'
  done
}

###############################################################################
# FlightAware: airport info + delays
###############################################################################
fa_airport() {
  local code="$1"
  local response
  response=$(fa_curl "/airports/${code}")
  local err
  err=$(echo "$response" | jq -r '.title // .error // empty' 2>/dev/null)
  if [[ -n "$err" ]]; then
    echo "FlightAware API error: $err" >&2
    return 1
  fi

  if [[ "$raw" -eq 1 ]]; then
    echo "$response"
    # Also fetch delays
    local delays
    delays=$(fa_curl "/airports/${code}/delays")
    echo "$delays"
    return 0
  fi

  local name icao iata city state tz elev
  name=$(echo "$response" | jq -r '.name // "?"')
  icao=$(echo "$response" | jq -r '.code_icao // "?"')
  iata=$(echo "$response" | jq -r '.code_iata // "?"')
  city=$(echo "$response" | jq -r '.city // "?"')
  state=$(echo "$response" | jq -r '.state // empty')
  tz=$(echo "$response"   | jq -r '.timezone // "?"')
  elev=$(echo "$response" | jq -r '.elevation // "?"')

  local location="$city"
  [[ -n "$state" ]] && location="$city, $state"

  printf '🛫 %s (%s / %s)\n' "$name" "$iata" "$icao"
  printf '   Location:  %s\n' "$location"
  printf '   Timezone:  %s\n' "$tz"
  printf '   Elevation: %s ft\n' "$elev"

  # Fetch delay info
  local delays
  delays=$(fa_curl "/airports/${code}/delays" 2>/dev/null) || true
  local delay_cat
  delay_cat=$(echo "$delays" | jq -r '.category // empty' 2>/dev/null)
  if [[ -n "$delay_cat" ]]; then
    local delay_secs delay_min
    delay_secs=$(echo "$delays" | jq -r '.delay_secs // 0')
    delay_min=$(( delay_secs / 60 ))
    printf '   ⚠️  Delay:   %s (%d min)\n' "$delay_cat" "$delay_min"
    echo "$delays" | jq -r '.reasons[]? | "              \(.reason) (\(.category), \(.delay_secs / 60 | floor) min)"'
  else
    printf '   Delays:    None reported\n'
  fi
  printf '   Source:    FlightAware\n\n'
}

###############################################################################
# FlightAware: departures
###############################################################################
fa_departures() {
  local code="$1"
  local response
  response=$(fa_curl "/airports/${code}/flights/scheduled_departures?max_pages=1")
  local err
  err=$(echo "$response" | jq -r '.title // .error // empty' 2>/dev/null)
  if [[ -n "$err" ]]; then
    echo "FlightAware API error: $err" >&2
    return 1
  fi
  if [[ "$raw" -eq 1 ]]; then
    echo "$response"
    return 0
  fi

  local count
  count=$(echo "$response" | jq '.scheduled_departures | if type == "array" then length else 0 end' 2>/dev/null)
  if [[ "${count:-0}" -eq 0 ]]; then
    echo "No departures found for '$code'." >&2
    return 1
  fi

  printf '🛫 Departures from %s (Source: FlightAware)\n\n' "$code"
  echo "$response" | jq -c '.scheduled_departures[]' | head -20 | while IFS= read -r fl; do
    local id dest_name dest_code sched_off est_off status cancelled
    id=$(echo "$fl"        | jq -r '.ident_iata // .ident // "?"')
    dest_name=$(echo "$fl" | jq -r '.destination.name // "?"')
    dest_code=$(echo "$fl" | jq -r '.destination.code_iata // .destination.code // "?"')
    sched_off=$(echo "$fl" | jq -r '.scheduled_out // .scheduled_off // empty')
    est_off=$(echo "$fl"   | jq -r '.estimated_out // .estimated_off // empty')
    status=$(echo "$fl"    | jq -r '.status // empty')
    cancelled=$(echo "$fl" | jq -r '.cancelled // false')

    local orig_tz
    orig_tz=$(echo "$fl" | jq -r '.origin.timezone // "UTC"')
    local sched_fmt est_fmt
    sched_fmt=$(fmt_time "$sched_off" "$orig_tz")
    est_fmt=$(fmt_time "${est_off:-$sched_off}" "$orig_tz")

    local status_str="${status:-Scheduled}"
    [[ "$cancelled" == "true" ]] && status_str="Cancelled"

    printf '  %-10s → %-30s  Sched: %s  Est: %s  [%s]\n' \
      "$id" "$dest_name ($dest_code)" "$sched_fmt" "$est_fmt" "$status_str"
  done
  echo ""
}

###############################################################################
# FlightAware: arrivals
###############################################################################
fa_arrivals() {
  local code="$1"
  local response
  response=$(fa_curl "/airports/${code}/flights/scheduled_arrivals?max_pages=1")
  local err
  err=$(echo "$response" | jq -r '.title // .error // empty' 2>/dev/null)
  if [[ -n "$err" ]]; then
    echo "FlightAware API error: $err" >&2
    return 1
  fi
  if [[ "$raw" -eq 1 ]]; then
    echo "$response"
    return 0
  fi

  local count
  count=$(echo "$response" | jq '.scheduled_arrivals | if type == "array" then length else 0 end' 2>/dev/null)
  if [[ "${count:-0}" -eq 0 ]]; then
    echo "No arrivals found for '$code'." >&2
    return 1
  fi

  printf '🛬 Arrivals at %s (Source: FlightAware)\n\n' "$code"
  echo "$response" | jq -c '.scheduled_arrivals[]' | head -20 | while IFS= read -r fl; do
    local id orig_name orig_code sched_on est_on status cancelled
    id=$(echo "$fl"        | jq -r '.ident_iata // .ident // "?"')
    orig_name=$(echo "$fl" | jq -r '.origin.name // "?"')
    orig_code=$(echo "$fl" | jq -r '.origin.code_iata // .origin.code // "?"')
    sched_on=$(echo "$fl"  | jq -r '.scheduled_in // .scheduled_on // empty')
    est_on=$(echo "$fl"    | jq -r '.estimated_in // .estimated_on // empty')
    status=$(echo "$fl"    | jq -r '.status // empty')
    cancelled=$(echo "$fl" | jq -r '.cancelled // false')

    local dest_tz
    dest_tz=$(echo "$fl" | jq -r '.destination.timezone // "UTC"')
    local sched_fmt est_fmt
    sched_fmt=$(fmt_time "$sched_on" "$dest_tz")
    est_fmt=$(fmt_time "${est_on:-$sched_on}" "$dest_tz")

    local status_str="${status:-Scheduled}"
    [[ "$cancelled" == "true" ]] && status_str="Cancelled"

    printf '  %-10s ← %-30s  Sched: %s  Est: %s  [%s]\n' \
      "$id" "$orig_name ($orig_code)" "$sched_fmt" "$est_fmt" "$status_str"
  done
  echo ""
}

###############################################################################
# FlightAware: route (origin → destination)
###############################################################################
fa_route() {
  local orig="$1" dest="$2"
  local response
  response=$(fa_curl "/airports/${orig}/flights/to/${dest}?max_pages=1")
  local err
  err=$(echo "$response" | jq -r '.title // .error // empty' 2>/dev/null)
  if [[ -n "$err" ]]; then
    echo "FlightAware API error: $err" >&2
    return 1
  fi
  if [[ "$raw" -eq 1 ]]; then
    echo "$response"
    return 0
  fi

  local count
  count=$(echo "$response" | jq '.flights | if type == "array" then length else 0 end' 2>/dev/null)
  if [[ "${count:-0}" -eq 0 ]]; then
    echo "No flights found between $orig and $dest." >&2
    return 1
  fi

  printf '✈️  Flights from %s → %s (Source: FlightAware)\n\n' "$orig" "$dest"
  echo "$response" | jq -c '.flights[]' | while IFS= read -r entry; do
    echo "$entry" | jq -c '.segments[]' | while IFS= read -r fl; do
      local id oper sched_out est_out status
      id=$(echo "$fl"        | jq -r '.ident_iata // .ident // "?"')
      oper=$(echo "$fl"      | jq -r '.operator // "?"')
      sched_out=$(echo "$fl" | jq -r '.scheduled_out // .scheduled_off // empty')
      est_out=$(echo "$fl"   | jq -r '.estimated_out // .estimated_off // empty')
      status=$(echo "$fl"    | jq -r '.status // "Scheduled"')

      local orig_tz
      orig_tz=$(echo "$fl" | jq -r '.origin.timezone // "UTC"')
      local sched_fmt
      sched_fmt=$(fmt_time "$sched_out" "$orig_tz")

      printf '  %-10s (%s)  Departs: %s  [%s]\n' "$id" "$oper" "$sched_fmt" "$status"
    done
  done
  echo ""
}

###############################################################################
# AviationStack fallback: flight status
###############################################################################
as_flight() {
  local ident="$1"
  local response
  response=$(as_curl "flights" "&flight_iata=$ident")

  local err
  err=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
  if [[ -n "$err" ]]; then
    echo "AviationStack API error: $err" >&2
    return 1
  fi

  local count
  count=$(echo "$response" | jq '.data | if type == "array" then length else 0 end' 2>/dev/null)
  if [[ "${count:-0}" -eq 0 ]]; then
    echo "No results found for '$ident' via AviationStack." >&2
    return 1
  fi

  if [[ "$raw" -eq 1 ]]; then
    echo "$response"
    return 0
  fi

  echo "$response" | jq -c '.data[]' | while IFS= read -r flight; do
    local flight_iata airline status
    flight_iata=$(echo "$flight"  | jq -r '.flight.iata // .flight.icao // "?"')
    airline=$(echo "$flight"      | jq -r '.airline.name // "Unknown Airline"')
    status=$(echo "$flight"       | jq -r '.flight_status // "?"')

    local dep_airport dep_iata dep_tz dep_terminal dep_gate dep_delay dep_sched dep_est dep_act
    dep_airport=$(echo "$flight"  | jq -r '.departure.airport // "?"')
    dep_iata=$(echo "$flight"     | jq -r '.departure.iata // "?"')
    dep_tz=$(echo "$flight"       | jq -r '.departure.timezone // "UTC"')
    dep_terminal=$(echo "$flight" | jq -r '.departure.terminal // empty')
    dep_gate=$(echo "$flight"     | jq -r '.departure.gate // empty')
    dep_delay=$(echo "$flight"    | jq -r '.departure.delay // empty')
    dep_sched=$(echo "$flight"    | jq -r '.departure.scheduled // empty')
    dep_est=$(echo "$flight"      | jq -r '.departure.estimated // empty')
    dep_act=$(echo "$flight"      | jq -r '.departure.actual // empty')

    local arr_airport arr_iata arr_tz arr_terminal arr_sched arr_est arr_act
    arr_airport=$(echo "$flight"  | jq -r '.arrival.airport // "?"')
    arr_iata=$(echo "$flight"     | jq -r '.arrival.iata // "?"')
    arr_tz=$(echo "$flight"       | jq -r '.arrival.timezone // "UTC"')
    arr_terminal=$(echo "$flight" | jq -r '.arrival.terminal // empty')
    arr_sched=$(echo "$flight"    | jq -r '.arrival.scheduled // empty')
    arr_est=$(echo "$flight"      | jq -r '.arrival.estimated // empty')
    arr_act=$(echo "$flight"      | jq -r '.arrival.actual // empty')

    local dep_sched_fmt dep_actual_fmt arr_sched_fmt arr_actual_fmt
    dep_sched_fmt=$(fmt_time_as "$dep_sched" "$dep_tz")
    dep_actual_fmt=$(fmt_time_as "${dep_act:-$dep_est}" "$dep_tz")
    arr_sched_fmt=$(fmt_time_as "$arr_sched" "$arr_tz")
    arr_actual_fmt=$(fmt_time_as "${arr_act:-$arr_est}" "$arr_tz")

    local term_str=""
    [[ -n "$dep_terminal" ]] && term_str=" Terminal $dep_terminal"
    [[ -n "$dep_gate" ]]     && term_str="${term_str}, Gate $dep_gate"
    local arr_term_str=""
    [[ -n "$arr_terminal" ]] && arr_term_str=" Terminal $arr_terminal"
    local delay_str="none"
    [[ -n "$dep_delay" && "$dep_delay" != "null" ]] && delay_str="${dep_delay} min dep"

    printf '✈️  %s (%s)\n' "$flight_iata" "$airline"
    printf '    Status:    %s\n' "$status"
    printf '    From:      %s (%s)%s\n' "$dep_airport" "$dep_iata" "$term_str"
    printf '    To:        %s (%s)%s\n' "$arr_airport" "$arr_iata" "$arr_term_str"
    printf '    Departure: %s (sched) → %s\n' "$dep_sched_fmt" "$dep_actual_fmt"
    printf '    Arrival:   %s (sched) → %s\n' "$arr_sched_fmt" "$arr_actual_fmt"
    printf '    Delay:     %s\n' "$delay_str"
    printf '    Source:    AviationStack (fallback)\n\n'
  done
}

###############################################################################
# Dispatch: try FlightAware first, fall back to AviationStack
###############################################################################
try_fa_then_fallback() {
  local fa_func="$1"
  shift
  local as_func="${1:-}"
  shift || true

  if fa_available; then
    if "$fa_func" "$@"; then
      return 0
    fi
    echo "⚠️  FlightAware failed; trying AviationStack fallback..." >&2
  fi

  if [[ -n "$as_func" ]] && as_available; then
    "$as_func" "$@"
    return $?
  fi

  if [[ -z "$as_func" ]]; then
    echo "Error: This subcommand is only available with FlightAware. Set FLIGHTAWARE_API_KEY." >&2
  elif ! as_available; then
    echo "Error: No working API available. Set FLIGHTAWARE_API_KEY or AVIATIONSTACK_API_KEY." >&2
  fi
  return 1
}

###############################################################################
# Main dispatch
###############################################################################
case "$cmd" in
  flight)
    try_fa_then_fallback fa_flight as_flight "$ident"
    ;;
  airport)
    try_fa_then_fallback fa_airport "" "$airport_code"
    ;;
  departures)
    try_fa_then_fallback fa_departures "" "$airport_code"
    ;;
  arrivals)
    try_fa_then_fallback fa_arrivals "" "$airport_code"
    ;;
  route)
    try_fa_then_fallback fa_route "" "$orig_code" "$dest_code"
    ;;
esac
