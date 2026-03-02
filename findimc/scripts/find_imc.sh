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

hours=4
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

if ! [[ "$hours" =~ ^[0-9]+$ && "$max_areas" =~ ^[0-9]+$ && "$airports_per_area" =~ ^[0-9]+$ && "$metar_hours" =~ ^[0-9]+$ ]]; then
  echo "Error: --hours, --max-areas, --airports-per-area, and --metar-hours must be integers." >&2
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

sigmet_response="$(curl -sS -A "$USER_AGENT" "${BASE_URL}/airsigmet?format=json&hours=${hours}")"

if [[ -z "$sigmet_response" || "$sigmet_response" == "[]" || "$sigmet_response" == "null" ]]; then
  if [[ "$json_output" == "true" ]]; then
    jq -n --arg bbox "$search_bbox" --arg countries "$countries_csv" '{
      summary: {
        search_bbox: $bbox,
        countries: ($countries | split(",")),
        significant_weather_areas_analyzed: 0,
        candidate_airports_queried: 0,
        airports_imc_count: 0
      },
      areas: [],
      message: "No active SIGMET/AIRMET weather areas found in the requested time window."
    }'
  else
    echo "No active SIGMET/AIRMET weather areas found in the requested time window."
  fi
  exit 0
fi

areas_json="$(echo "$sigmet_response" | jq --arg bbox "$search_bbox" --argjson max_areas "$max_areas" '
  def parse_bbox($s):
    ($s | split(",") | map(tonumber)) as $b
    | { min_lat: $b[0], min_lon: $b[1], max_lat: $b[2], max_lon: $b[3] };
  def intersects($a; $b):
    ($a.max_lat >= $b.min_lat) and
    ($a.min_lat <= $b.max_lat) and
    ($a.max_lon >= $b.min_lon) and
    ($a.min_lon <= $b.max_lon);
  def weather_signal:
    ((.hazard // "" | ascii_upcase) | test("CONVECTIVE|THUNDER|TS|PRECIP|RAIN|SNOW|ICE|FZRA|SEV")) or
    ((.rawAirSigmet // "" | ascii_upcase) | test("\\+TS|TSRA|TS\\b|\\+RA|\\-RA|SHRA|SNOW|FZRA|CONVECTIVE"));

  parse_bbox($bbox) as $search
  | [ .[]
      | . as $row
      | select((.coords | type) == "array" and (.coords | length) > 0)
      | {
          area_id: "\($row.airSigmetType // "SIGMET")-\($row.seriesId // "NA")",
          hazard: ($row.hazard // "UNKNOWN"),
          severity: ($row.severity // 0),
          valid_from: ($row.validTimeFrom // 0),
          valid_to: ($row.validTimeTo // 0),
          min_lat: ([.coords[].lat] | min),
          min_lon: ([.coords[].lon] | min),
          max_lat: ([.coords[].lat] | max),
          max_lon: ([.coords[].lon] | max),
          headline: (($row.rawAirSigmet // "") | split("\n") | .[0:3] | join(" "))
        }
      | select(weather_signal)
      | select(intersects(.; $search))
    ]
  | sort_by(.severity, .valid_to)
  | reverse
  | .[0:$max_areas]
')"

area_count="$(echo "$areas_json" | jq 'length')"
if [[ "$area_count" -eq 0 ]]; then
  if [[ "$json_output" == "true" ]]; then
    jq -n --arg bbox "$search_bbox" --arg countries "$countries_csv" '{
      summary: {
        search_bbox: $bbox,
        countries: ($countries | split(",")),
        significant_weather_areas_analyzed: 0,
        candidate_airports_queried: 0,
        airports_imc_count: 0
      },
      areas: [],
      message: "No significant storm/precip areas intersected the search bbox."
    }'
  else
    echo "No significant storm/precip areas intersected search bbox ${search_bbox}."
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
    jq -n --arg bbox "$search_bbox" --arg countries "$countries_csv" --argjson areas "$areas_json" '{
      summary: {
        search_bbox: $bbox,
        countries: ($countries | split(",")),
        significant_weather_areas_analyzed: ($areas | length),
        candidate_airports_queried: 0,
        airports_imc_count: 0
      },
      areas: ($areas | map({
        area_id,
        hazard,
        severity,
        area_bbox: "\(.min_lat),\(.min_lon),\(.max_lat),\(.max_lon)",
        bulletin: .headline,
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
metar_json="$(curl -sS -A "$USER_AGENT" "${BASE_URL}/metar?ids=${metar_ids_csv}&format=json&hours=${metar_hours}" || true)"

declare -A metar_raw_by_airport=()
declare -A metar_cat_by_airport=()
declare -A imc_cat_by_airport=()

if [[ -n "$metar_json" && "$metar_json" != "[]" && "$metar_json" != "null" ]]; then
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
fi

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
      hazard,
      severity,
      area_bbox: "\(.min_lat),\(.min_lon),\(.max_lat),\(.max_lon)",
      bulletin: .headline,
      checked_airports: $checked
    }')"

    areas_output="$(echo "$areas_output" | jq --argjson area "$area_json" '. + [$area]')"
  done

  jq -n \
    --arg bbox "$search_bbox" \
    --arg countries "$countries_csv" \
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
  hazard="$(echo "$area" | jq -r '.hazard')"
  severity="$(echo "$area" | jq -r '.severity')"
  bbox="$(echo "$area" | jq -r '"\(.min_lat),\(.min_lon),\(.max_lat),\(.max_lon)"')"
  headline="$(echo "$area" | jq -r '.headline')"

  echo "Area $((idx + 1)): ${area_id}"
  echo "  Hazard: ${hazard}  Severity: ${severity}"
  echo "  Area bbox: ${bbox}"
  echo "  Bulletin: ${headline}"

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
