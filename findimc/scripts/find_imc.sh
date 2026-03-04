#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://aviationweather.gov/api/data"
USER_AGENT="OpenClaw-FindIMC/1.0"
DEFAULT_SEARCH_BBOX="18,-170,72,-52"
METAR_BACKFILL_POOL_MULTIPLIER=8

usage() {
  cat >&2 <<'EOF'
Usage: find_imc.sh [flags]

Find active storm/precip weather areas, pick nearby US airports, and report
airports currently in MVFR/IFR/LIFR from METAR flight category.

Flags:
  --hours <N>                Look-back window for SIGMET/AIRMET scan (default: 4)
  --source <MODE>            Weather area source: gairmet, sigmet, both (default: both)
  --forecast-hour <N>        G-AIRMET forecast hour filter; -1 = auto/all (default: -1)
  --search-bbox <BOX>        Search extent lat0,lon0,lat1,lon1 (default: 18,-170,72,-52)
                             Default includes CONUS, AK, and HI while excluding Europe/Asia.
  --countries <LIST>         Comma-separated ISO country codes for airports (default: US)
  --max-areas <N>            Max significant weather areas to analyze (default: 5)
  --airports-per-area <N>    Candidate US airports per area (default: 5)
  --metar-hours <N>          METAR look-back hours (default: 2)
  --json                     Emit structured JSON output
  --debug                    Show full METAR JSON records for checked airports
  --debug-airport <ICAO>     Limit debug METAR output to one airport
  --help                     Show this help

Examples:
  find_imc.sh
  find_imc.sh --max-areas 8 --airports-per-area 6
  find_imc.sh --search-bbox 18,-170,72,-52 --hours 6
  find_imc.sh --source gairmet --forecast-hour 3
  find_imc.sh --countries US,CA --json
  find_imc.sh --debug --debug-airport KDEN
EOF
  exit 1
}

require_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Error: required binary '$bin' is not installed." >&2
    exit 1
  fi
}

validate_json_response() {
  local response="$1"
  local api_name="$2"
  
  if [[ -z "$response" ]]; then
    echo "Error: ${api_name} API returned empty response." >&2
    return 1
  fi
  
  if ! echo "$response" | jq empty 2>/dev/null; then
    echo "Error: ${api_name} API returned invalid JSON." >&2
    if [[ "$debug_mode" == "true" || "${FINDIMC_VERBOSE:-false}" == "true" ]]; then
      echo "  Response preview (first 500 chars): ${response:0:500}" >&2
      echo "  Full response: $response" >&2
    fi
    return 1
  fi
  
  debug_output "${api_name} response is valid JSON"
  return 0
}

debug_output() {
  if [[ "$debug_mode" == "true" || "${FINDIMC_VERBOSE:-false}" == "true" ]]; then
    echo "DEBUG: $*" >&2
  fi
}

hours=4
source_mode="both"
forecast_hour=-1
search_bbox="$DEFAULT_SEARCH_BBOX"
max_areas=5
airports_per_area=5
metar_hours=2
countries_csv="US"
json_output="false"
debug_mode="false"
debug_airport=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours)
      hours="$2"
      shift 2
      ;;
    --search-bbox)
      search_bbox="$2"
      shift 2
      ;;
    --source)
      source_mode="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
      shift 2
      ;;
    --forecast-hour)
      forecast_hour="$2"
      shift 2
      ;;
    --max-areas)
      max_areas="$2"
      shift 2
      ;;
    --countries)
      countries_csv="$2"
      shift 2
      ;;
    --airports-per-area)
      airports_per_area="$2"
      shift 2
      ;;
    --metar-hours)
      metar_hours="$2"
      shift 2
      ;;
    --json)
      json_output="true"
      shift
      ;;
    --debug)
      debug_mode="true"
      shift
      ;;
    --debug-airport)
      debug_mode="true"
      debug_airport="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Error: unknown flag '$1'" >&2
      usage
      ;;
  esac
done

if ! [[ "$hours" =~ ^[0-9]+$ && "$forecast_hour" =~ ^-?[0-9]+$ && "$max_areas" =~ ^[0-9]+$ && "$airports_per_area" =~ ^[0-9]+$ && "$metar_hours" =~ ^[0-9]+$ ]]; then
  echo "Error: --hours, --forecast-hour, --max-areas, --airports-per-area, and --metar-hours must be integers." >&2
  exit 1
fi

if [[ "$source_mode" != "gairmet" && "$source_mode" != "sigmet" && "$source_mode" != "both" ]]; then
  echo "Error: --source must be one of: gairmet, sigmet, both." >&2
  exit 1
fi

if [[ "$max_areas" -lt 1 || "$airports_per_area" -lt 1 ]]; then
  echo "Error: --max-areas and --airports-per-area must be >= 1." >&2
  exit 1
fi

if ! echo "$search_bbox" | jq -e -R 'split(",") | length == 4 and all(.[]; test("^-?[0-9]+(\\.[0-9]+)?$"))' >/dev/null; then
  echo "Error: --search-bbox must be lat0,lon0,lat1,lon1." >&2
  exit 1
fi

countries_csv="$(echo "$countries_csv" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
if ! echo "$countries_csv" | jq -e -R 'split(",") | map(select(length > 0)) | length > 0 and all(.[]; test("^[A-Z]{2}$"))' >/dev/null; then
  echo "Error: --countries must be comma-separated ISO-3166 alpha-2 codes (example: US,CA)." >&2
  exit 1
fi
countries_json="$(echo "$countries_csv" | jq -c -R 'split(",") | map(select(length > 0))')"

require_bin curl
require_bin jq

if [[ -n "$debug_airport" && ! "$debug_airport" =~ ^[A-Z0-9]{3,5}$ ]]; then
  echo "Error: --debug-airport must be a valid ICAO-like code (3-5 alphanumeric chars)." >&2
  exit 1
fi

gairmet_response='[]'
sigmet_response='[]'

if [[ "$source_mode" == "gairmet" || "$source_mode" == "both" ]]; then
  gairmet_response="$(curl -sS -A "$USER_AGENT" "${BASE_URL}/gairmet?format=json&hazard=IFR" || echo '[]')"
  debug_output "G-AIRMET API response received (${#gairmet_response} chars)"
  if ! validate_json_response "$gairmet_response" "G-AIRMET"; then
    echo "Continuing with empty G-AIRMET response..." >&2
    gairmet_response='[]'
  fi
fi

if [[ "$source_mode" == "sigmet" || "$source_mode" == "both" ]]; then
  sigmet_response="$(curl -sS -A "$USER_AGENT" "${BASE_URL}/airsigmet?format=json&hours=${hours}" || echo '[]')"
  debug_output "SIGMET API response received (${#sigmet_response} chars)"
  if ! validate_json_response "$sigmet_response" "SIGMET"; then
    echo "Continuing with empty SIGMET response..." >&2
    sigmet_response='[]'
  fi
fi

areas_json="$(jq -n \
  --arg bbox "$search_bbox" \
  --arg source "$source_mode" \
  --argjson max_areas "$max_areas" \
  --argjson forecast_hour "$forecast_hour" \
  --argjson gairmet "$gairmet_response" \
  --argjson sigmet "$sigmet_response" '
  def parse_bbox($s):
    ($s | split(",") | map(tonumber)) as $b
    | { min_lat: $b[0], min_lon: $b[1], max_lat: $b[2], max_lon: $b[3] };
  def intersects($a; $b):
    ($a.max_lat >= $b.min_lat) and
    ($a.min_lat <= $b.max_lat) and
    ($a.max_lon >= $b.min_lon) and
    ($a.min_lon <= $b.max_lon);
  def sigmet_weather_signal:
    ((.hazard // "" | ascii_upcase) | test("CONVECTIVE|THUNDER|TS|PRECIP|RAIN|SNOW|ICE|FZRA|SEV")) or
    ((.rawAirSigmet // "" | ascii_upcase) | test("\\+TS|TSRA|TS\\b|\\+RA|\\-RA|SHRA|SNOW|FZRA|CONVECTIVE"));
  def airmet_ifr_signal:
    ((.hazard // "" | ascii_upcase) | test("IFR|MT_OBSC")) or
    ((.rawAirSigmet // "" | ascii_upcase) | test("CIG|VIS|IFR|OBSC|BR|FG"));
  def gairmet_areas:
    [ $gairmet[]
      | select((.hazard // "") == "IFR")
      | select($forecast_hour < 0 or ((.forecastHour // -1) == $forecast_hour))
      | select((.coords | type) == "array" and (.coords | length) > 0)
      | {
          area_id: "GAIRMET-\(.tag // "NA")-FH\(.forecastHour // 0)",
          source: "gairmet",
          hazard: (.hazard // "IFR"),
          severity: 20,
          valid_from: (.issueTime // 0),
          valid_to: (.expireTime // 0),
          min_lat: ([.coords[].lat | tonumber] | min),
          min_lon: ([.coords[].lon | tonumber] | min),
          max_lat: ([.coords[].lat | tonumber] | max),
          max_lon: ([.coords[].lon | tonumber] | max),
          headline: "G-AIRMET IFR \(.tag // "NA") FH\(.forecastHour // 0)",
          due_to: (.due_to // ""),
          product: (.product // "SIERRA")
        }
    ];
  def sigmet_areas:
    [ $sigmet[]
      | . as $row
      | select((.coords | type) == "array" and (.coords | length) > 0)
      | select(
          ((.airSigmetType // "") == "SIGMET" and sigmet_weather_signal) or
          ((.airSigmetType // "") == "AIRMET" and airmet_ifr_signal)
        )
      | {
          area_id: "\($row.airSigmetType // "SIGMET")-\($row.seriesId // "NA")",
          source: ((.airSigmetType // "SIGMET") | ascii_downcase),
          hazard: ($row.hazard // "UNKNOWN"),
          severity: (if ($row.airSigmetType // "") == "AIRMET" then 12 else ($row.severity // 5) end),
          valid_from: ($row.validTimeFrom // 0),
          valid_to: ($row.validTimeTo // 0),
          min_lat: ([.coords[].lat] | min),
          min_lon: ([.coords[].lon] | min),
          max_lat: ([.coords[].lat] | max),
          max_lon: ([.coords[].lon] | max),
          headline: (($row.rawAirSigmet // "") | split("\n") | .[0:3] | join(" ")),
          due_to: "",
          product: null
        }
    ];

  parse_bbox($bbox) as $search
  | ((if $source == "gairmet" then gairmet_areas
      elif $source == "sigmet" then sigmet_areas
      else (gairmet_areas + sigmet_areas)
      end)
    | map(select(intersects(.; $search))))
  | sort_by(.severity, .valid_to)
  | reverse
  | .[0:$max_areas]
')"

area_count="$(echo "$areas_json" | jq 'length')"
if [[ "$area_count" -eq 0 ]]; then
  if [[ "$json_output" == "true" ]]; then
    jq -n --arg bbox "$search_bbox" --arg countries "$countries_csv" --arg source "$source_mode" --argjson fh "$forecast_hour" '{
      summary: {
        search_bbox: $bbox,
        countries: ($countries | split(",")),
        source: $source,
        forecast_hour: $fh,
        significant_weather_areas_analyzed: 0,
        candidate_airports_queried: 0,
        airports_imc_count: 0
      },
      areas: [],
      message: "No weather areas matched the selected source and filters in the search bbox."
    }'
  else
    echo "No weather areas matched source '${source_mode}' (forecast hour ${forecast_hour}) in search bbox ${search_bbox}."
  fi
  exit 0
fi

declare -a area_rows
declare -a area_candidate_pool_csv
declare -a area_airports_csv
declare -a all_airports
declare -A seen_airport=()

mapfile -t area_rows < <(echo "$areas_json" | jq -c '.[]')

for idx in "${!area_rows[@]}"; do
  area="${area_rows[$idx]}"
  area_bbox="$(echo "$area" | jq -r '"\(.min_lat),\(.min_lon),\(.max_lat),\(.max_lon)"')"
  pool_limit=$((airports_per_area * METAR_BACKFILL_POOL_MULTIPLIER))

  stations_response="$(curl -sS -A "$USER_AGENT" "${BASE_URL}/stationinfo?format=json&bbox=${area_bbox}")"
  debug_output "StationInfo API response for area $((idx + 1)) received (${#stations_response} chars)"
  
  if ! validate_json_response "$stations_response" "StationInfo (area $((idx + 1)))"; then
    debug_output "Skipping invalid StationInfo response for area $((idx + 1))"
    area_candidate_pool_csv[$idx]=""
    area_airports_csv[$idx]=""
    continue
  fi

  mapfile -t area_pool_airports < <(echo "$stations_response" | jq -r --argjson countries "$countries_json" '
    [ .[]
      | select((.country // "") as $c | ($countries | index($c)) != null)
      | select(.icaoId != null)
      | select((.siteType | type) == "array")
      | select((.siteType | length) == 0 or (.siteType | index("METAR") != null))
      | { icaoId: .icaoId, priority: (.priority // 0) }
    ]
    | sort_by(.priority)
    | reverse
    | .[].icaoId
  ' | awk '!seen[$0]++' | head -n "$pool_limit")

  if [[ "${#area_pool_airports[@]}" -eq 0 ]]; then
    area_candidate_pool_csv[$idx]=""
    area_airports_csv[$idx]=""
    continue
  fi

  area_candidate_pool_csv[$idx]="$(IFS=,; echo "${area_pool_airports[*]}")"

  for code in "${area_pool_airports[@]}"; do
    if [[ -z "${seen_airport[$code]:-}" ]]; then
      seen_airport[$code]=1
      all_airports+=("$code")
    fi
  done
done

if [[ "${#all_airports[@]}" -eq 0 ]]; then
  if [[ "$json_output" == "true" ]]; then
    jq -n --arg bbox "$search_bbox" --arg countries "$countries_csv" --arg source "$source_mode" --argjson fh "$forecast_hour" --argjson areas "$areas_json" '{
      summary: {
        search_bbox: $bbox,
        countries: ($countries | split(",")),
        source: $source,
        forecast_hour: $fh,
        significant_weather_areas_analyzed: ($areas | length),
        candidate_airports_queried: 0,
        airports_imc_count: 0
      },
      areas: ($areas | map({
        area_id,
        source,
        hazard,
        due_to,
        product,
        severity,
        area_bbox: "\(.min_lat),\(.min_lon),\(.max_lat),\(.max_lon)",
        synopsis: .headline,
        checked_airports: []
      })),
      message: "No airports found inside significant weather-area bounding boxes for selected countries."
    }'
  else
    echo "No airports found inside significant weather-area bounding boxes for selected countries (${countries_csv})."
  fi
  exit 0
fi

metar_ids_csv="$(IFS=,; echo "${all_airports[*]}")"
debug_output "METAR IDs to query: count: ${#all_airports[@]}"

declare -A metar_raw_by_airport=()
declare -A metar_cat_by_airport=()
declare -A imc_cat_by_airport=()

# Batch METAR queries in chunks of 350 to stay under API's 400-station limit
metar_batch_size=350
for ((i=0; i < ${#all_airports[@]}; i+=metar_batch_size)); do
  batch_end=$((i + metar_batch_size))
  batch_codes=("${all_airports[@]:i:metar_batch_size}")
  batch_ids_csv="$(IFS=,; echo "${batch_codes[*]}")"
  
  debug_output "Querying METAR batch $((i/metar_batch_size + 1)): ${#batch_codes[@]} airports"
  metar_json="$(curl -sS -A "$USER_AGENT" "${BASE_URL}/metar?ids=${batch_ids_csv}&format=json&hours=${metar_hours}" || true)"
  debug_output "METAR batch response: ${#metar_json} chars"
  
  if [[ -n "$metar_json" ]]; then
    if ! validate_json_response "$metar_json" "METAR (batch $((i/metar_batch_size + 1)))"; then
      debug_output "Invalid METAR response for batch, skipping"
      continue
    fi
  fi

  if [[ -z "$metar_json" || "$metar_json" == "[]" || "$metar_json" == "null" ]]; then
    continue
  fi
  
  # Check if response is an error object instead of an array
  if echo "$metar_json" | jq -e '.status == "error"' >/dev/null 2>&1; then
    error_msg="$(echo "$metar_json" | jq -r '.error // "unknown error"')"
    debug_output "METAR API returned error: $error_msg"
    continue
  fi
  
  mapfile -t metar_rows < <(echo "$metar_json" | jq -c '.[]')

  for row in "${metar_rows[@]}"; do
    airport="$(echo "$row" | jq -r '.icaoId // empty')"
    category="$(echo "$row" | jq -r '
      def frac_to_num($s):
        if ($s | test("^[0-9]+/[0-9]+$")) then
          ($s | split("/") | (.[0] | tonumber) / (.[1] | tonumber))
        else
          null
        end;

      def parse_vis:
        (.visib? // empty) as $v
        | if ($v | type) == "number" then
            $v
          elif ($v | type) != "string" then
            null
          else
            ($v
              | gsub("SM"; "")
              | gsub("\\+"; "")
              | sub("^P"; "")
              | sub("^M"; "")
              | gsub("\\s+"; " ")
              | sub("^ "; "")
              | sub(" $"; "")) as $s
            | if $s == "" then
                null
              elif ($s | test("^[0-9]+(\\.[0-9]+)?$")) then
                ($s | tonumber)
              elif ($s | test("^[0-9]+/[0-9]+$")) then
                (frac_to_num($s))
              elif ($s | test("^[0-9]+ [0-9]+/[0-9]+$")) then
                ($s | split(" ")) as $p
                | (($p[0] | tonumber) + (frac_to_num($p[1]) // 0))
              else
                null
              end
          end;

      def parse_ceiling:
        if (.clouds | type) == "array" then
          ([.clouds[]
            | select(((.cover // "") | test("^(BKN|OVC|VV)$")))
            | .base
            | numbers] | if length > 0 then min else null end)
        else
          null
        end;

      def derive_cat($vis; $ceil):
        if $vis == null and $ceil == null then
          "UNKNOWN"
        elif (($vis != null and $vis < 1) or ($ceil != null and $ceil < 500)) then
          "LIFR"
        elif (($vis != null and $vis < 3) or ($ceil != null and $ceil < 1000)) then
          "IFR"
        elif (($vis != null and $vis <= 5) or ($ceil != null and $ceil <= 3000)) then
          "MVFR"
        else
          "VFR"
        end;

      if (.fltCat? != null and .fltCat != "") then
        .fltCat
      else
        derive_cat(parse_vis; parse_ceiling)
      end
    ' )"

    if [[ -z "$airport" ]]; then
      continue
    fi

    metar_raw_by_airport[$airport]="$row"
    metar_cat_by_airport[$airport]="$category"

    if [[ "$category" == "MVFR" || "$category" == "IFR" || "$category" == "LIFR" ]]; then
      imc_cat_by_airport[$airport]="$category"
    fi
  done
done

# Build final per-area checked airports with METAR-first backfill.
for idx in "${!area_rows[@]}"; do
  pool_csv="${area_candidate_pool_csv[$idx]:-}"

  if [[ -z "$pool_csv" ]]; then
    area_airports_csv[$idx]=""
    continue
  fi

  IFS=',' read -r -a pool_codes <<< "$pool_csv"

  selected=()

  # First pass: airports with METAR records.
  for code in "${pool_codes[@]}"; do
    if [[ -n "${metar_raw_by_airport[$code]:-}" ]]; then
      selected+=("$code")
    fi
    if [[ "${#selected[@]}" -ge "$airports_per_area" ]]; then
      break
    fi
  done

  # Second pass: fill any remaining slots with non-reporting candidates.
  if [[ "${#selected[@]}" -lt "$airports_per_area" ]]; then
    for code in "${pool_codes[@]}"; do
      skip=false
      for picked in "${selected[@]}"; do
        if [[ "$picked" == "$code" ]]; then
          skip=true
          break
        fi
      done

      if [[ "$skip" == false ]]; then
        selected+=("$code")
      fi

      if [[ "${#selected[@]}" -ge "$airports_per_area" ]]; then
        break
      fi
    done
  fi

  area_airports_csv[$idx]="$(IFS=,; echo "${selected[*]}")"
done

overall_imc_count="${#imc_cat_by_airport[@]}"

if [[ "$json_output" == "true" ]]; then
  areas_output='[]'

  for idx in "${!area_rows[@]}"; do
    area="${area_rows[$idx]}"
    csv="${area_airports_csv[$idx]:-}"
    checked='[]'

    if [[ -n "$csv" ]]; then
      IFS=',' read -r -a area_codes <<< "$csv"
      for code in "${area_codes[@]}"; do
        category="${metar_cat_by_airport[$code]:-UNKNOWN}"
        metar_record="${metar_raw_by_airport[$code]:-}"
        if [[ "$category" == "MVFR" || "$category" == "IFR" || "$category" == "LIFR" ]]; then
          is_imc=true
        else
          is_imc=false
        fi

        if [[ "$debug_mode" == "true" ]]; then
          checked="$(echo "$checked" | jq --arg icao "$code" --arg category "$category" --argjson imc "$is_imc" --argjson metar "${metar_record:-null}" '. + [{icao: $icao, flight_category: $category, imc: $imc, metar_record: $metar}]')"
        else
          checked="$(echo "$checked" | jq --arg icao "$code" --arg category "$category" --argjson imc "$is_imc" '. + [{icao: $icao, flight_category: $category, imc: $imc}]')"
        fi
      done
    fi

    area_json="$(echo "$area" | jq --argjson checked "$checked" '{
      area_id,
      source,
      hazard,
      due_to,
      product,
      severity,
      area_bbox: "\(.min_lat),\(.min_lon),\(.max_lat),\(.max_lon)",
      synopsis: .headline,
      checked_airports: $checked
    }')"

    areas_output="$(echo "$areas_output" | jq --argjson area "$area_json" '. + [$area]')"
  done

  jq -n \
    --arg bbox "$search_bbox" \
    --arg countries "$countries_csv" \
      --arg source "$source_mode" \
      --argjson forecast_hour "$forecast_hour" \
    --argjson debug "$( [[ "$debug_mode" == "true" ]] && echo true || echo false )" \
    --arg debug_airport "$debug_airport" \
    --argjson area_count "$area_count" \
    --argjson airport_count "${#all_airports[@]}" \
    --argjson imc_count "$overall_imc_count" \
    --argjson areas "$areas_output" \
    '{
      summary: {
        search_bbox: $bbox,
        countries: ($countries | split(",")),
        source: $source,
        forecast_hour: $forecast_hour,
        debug: $debug,
        debug_airport: (if $debug_airport == "" then null else $debug_airport end),
        significant_weather_areas_analyzed: $area_count,
        candidate_airports_queried: $airport_count,
        airports_imc_count: $imc_count
      },
      areas: $areas
    }'
  exit 0
fi

echo "findIMC weather scan"
echo "Search bbox: ${search_bbox}"
echo "Countries: ${countries_csv}"
echo "Source mode: ${source_mode}"
if [[ "$forecast_hour" -lt 0 ]]; then
  echo "G-AIRMET forecast hour: auto (all)"
else
  echo "G-AIRMET forecast hour: ${forecast_hour}"
fi
echo "Debug mode: ${debug_mode}"
if [[ -n "$debug_airport" ]]; then
  echo "Debug airport filter: ${debug_airport}"
fi
echo "Significant weather areas analyzed: ${area_count}"
echo "Candidate airports queried: ${#all_airports[@]}"
echo "Airports in MVFR/IFR/LIFR: ${overall_imc_count}"
echo

debug_airport_found=false

for idx in "${!area_rows[@]}"; do
  area="${area_rows[$idx]}"
  area_id="$(echo "$area" | jq -r '.area_id')"
  area_source="$(echo "$area" | jq -r '.source // "unknown"')"
  hazard="$(echo "$area" | jq -r '.hazard')"
  due_to="$(echo "$area" | jq -r '.due_to // ""')"
  product="$(echo "$area" | jq -r '.product // ""')"
  severity="$(echo "$area" | jq -r '.severity')"
  bbox="$(echo "$area" | jq -r '"\(.min_lat),\(.min_lon),\(.max_lat),\(.max_lon)"')"
  headline="$(echo "$area" | jq -r '.headline')"

  echo "Area $((idx + 1)): ${area_id}"
  echo "  Source: ${area_source}  Hazard: ${hazard}  Severity: ${severity}"
  if [[ -n "$product" ]]; then
    echo "  Product: ${product}"
  fi
  if [[ -n "$due_to" ]]; then
    echo "  Due To: ${due_to}"
  fi
  echo "  Area bbox: ${bbox}"
  echo "  Synopsis: ${headline}"

  csv="${area_airports_csv[$idx]:-}"
  if [[ -z "$csv" ]]; then
    echo "  Airports: none found"
    echo
    continue
  fi

  IFS=',' read -r -a area_codes <<< "$csv"
  echo "  Airports checked: ${csv}"

  found_in_area=0
  for code in "${area_codes[@]}"; do
    category="${metar_cat_by_airport[$code]:-UNKNOWN}"
    echo "  ${code} => ${category}"

    if [[ -n "$debug_airport" && "$code" == "$debug_airport" ]]; then
      debug_airport_found=true
    fi

    if [[ "$debug_mode" == "true" ]]; then
      if [[ -n "$debug_airport" && "$code" != "$debug_airport" ]]; then
        :
      elif [[ -n "${metar_raw_by_airport[$code]:-}" ]]; then
        echo "    METAR JSON (${code}):"
        echo "${metar_raw_by_airport[$code]}" | jq '.' | sed 's/^/      /'
      else
        echo "    METAR JSON (${code}): null (no METAR in look-back window)"
      fi
    fi

    if [[ -n "${imc_cat_by_airport[$code]:-}" ]]; then
      found_in_area=1
      if [[ -n "${metar_raw_by_airport[$code]:-}" ]]; then
        echo "    Raw METAR: $(echo "${metar_raw_by_airport[$code]}" | jq -r '.rawOb // "N/A"')"
        echo "    Visibility: $(echo "${metar_raw_by_airport[$code]}" | jq -r '.visib // "N/A"')  Ceiling cover: $(echo "${metar_raw_by_airport[$code]}" | jq -r '.cover // "N/A"')"
      fi
      echo
    fi
  done

  if [[ "$found_in_area" -eq 0 ]]; then
    echo "  No airports in this area are currently MVFR/IFR/LIFR."
    echo
  fi
done

if [[ "$overall_imc_count" -eq 0 ]]; then
  echo "No currently-reported MVFR/IFR/LIFR airports were found in the selected weather areas."
fi

if [[ "$debug_mode" == "true" && -n "$debug_airport" && "$debug_airport_found" == "false" ]]; then
  echo "Debug airport ${debug_airport} was not in the selected candidate airports for this run."
fi
