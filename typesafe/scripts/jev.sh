#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# jev.sh — calibrated judgements from Jev (TypeSafe System One)
#
# Jev is not a chat model. You give it a `state` (the thing to judge) plus a
# map of named, typed questions; it returns calibrated probabilities. It never
# returns prose.
#
# Env vars:
#   TYPESAFE_API_KEY   — required. Falls back to ~/.openclaw/.env if unset.
###############################################################################

API_URL="https://api.typesafe.ai/v1/systemone"
DEFAULT_MODEL="jev-latest"
MAX_ATTEMPTS=3

usage() {
  cat >&2 <<'EOF'
Usage:
  jev.sh ask   --questions <file.json> [--state <text> | --state-file <file>] [flags]
  jev.sh noul  --question <text>       [--state <text> | --state-file <file>] [flags]
  jev.sh check

Subcommands:
  ask      Evaluate a committed question set against a state. This is the
           normal path: many questions, one request, one price.
  noul     One-shot yes/no. Prints a single probability between 0 and 1.
  check    Auth + connectivity smoke test. Takes no flags.

Flags:
  --questions <file>   JSON object mapping question id -> question object.
  --state <text>       The content to judge, as literal text. Quote it.
  --state-file <file>  The content to judge, read from a file. If the file is
                       valid JSON it is sent as structured state; otherwise it
                       is sent as a text string.
  --question <text>    (noul only) The yes/no question. Quote it.
  --true <desc>        (noul only) What "true" means.
  --false <desc>       (noul only) What "false" means.
  --model <id>         Default: jev-latest. Pin jev-1.13.0 once you have tuned
                       thresholds — the alias moves when TypeSafe ships.
  --raw                Emit the untouched JSON response instead of a summary.

Reading the output:
  noul   is a probability, not a boolean. 0.95 means "almost certainly yes",
         0.5 means "no idea". It carries no separate confidence.
  choice ships the picked option plus the full distribution and a confidence.
  score  ships a position on the spectrum, which may land between two levels.

Exit codes:
  0 ok   1 error (auth, validation, network, exhausted retries)   2 usage
EOF
  exit 2
}

[[ $# -lt 1 ]] && usage

cmd="$1"; shift
case "$cmd" in
  ask|noul|check) ;;
  -h|--help) usage ;;
  *) echo "Unknown subcommand: $cmd" >&2; usage ;;
esac

# Check dependencies
for dep in curl jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Error: '$dep' is not installed." >&2
    exit 1
  fi
done

questions_file=""
state_text=""
state_file=""
question_text=""
true_desc=""
false_desc=""
model="$DEFAULT_MODEL"
raw=0

# Set by build_state and api_post respectively. They assign to globals rather
# than printing, so that a fatal `exit` inside them is not swallowed by $( ).
STATE_JSON=""
RESPONSE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --questions)   [[ $# -lt 2 ]] && usage; questions_file="$2"; shift 2 ;;
    --state)       [[ $# -lt 2 ]] && usage; state_text="$2";     shift 2 ;;
    --state-file)  [[ $# -lt 2 ]] && usage; state_file="$2";     shift 2 ;;
    --question)    [[ $# -lt 2 ]] && usage; question_text="$2";  shift 2 ;;
    --true)        [[ $# -lt 2 ]] && usage; true_desc="$2";      shift 2 ;;
    --false)       [[ $# -lt 2 ]] && usage; false_desc="$2";     shift 2 ;;
    --model)       [[ $# -lt 2 ]] && usage; model="$2";          shift 2 ;;
    --raw)         raw=1; shift ;;
    -h|--help)     usage ;;
    *)             echo "Unknown flag: $1" >&2; usage ;;
  esac
done

###############################################################################
# API key resolution
#
# The gateway may or may not export .env into exec children, so fall back to
# reading ~/.openclaw/.env directly. Sourcing is best-effort: a malformed line
# in that file must not take the script down.
###############################################################################
resolve_key() {
  if [[ -n "${TYPESAFE_API_KEY:-}" ]]; then
    return 0
  fi
  local envfile="${HOME}/.openclaw/.env"
  if [[ -r "$envfile" ]]; then
    set +e
    set -a
    # shellcheck disable=SC1090
    . "$envfile" >/dev/null 2>&1
    set +a
    set -e
  fi
  if [[ -z "${TYPESAFE_API_KEY:-}" ]]; then
    echo "Error: TYPESAFE_API_KEY is not set, and ~/.openclaw/.env did not supply it." >&2
    echo "Get a key from the TypeSafe console and add it to ~/.openclaw/.env." >&2
    exit 1
  fi
}

###############################################################################
# Build the state as a JSON value.
#
# A JSON state file is passed through structurally (so questions can reference
# its fields by name); anything else becomes a JSON string.
###############################################################################
build_state() {
  if [[ -n "$state_file" ]]; then
    if [[ ! -r "$state_file" ]]; then
      echo "Error: cannot read state file: $state_file" >&2
      exit 1
    fi
    if jq -e . "$state_file" >/dev/null 2>&1; then
      STATE_JSON="$(jq -c . "$state_file")"
    else
      STATE_JSON="$(jq -Rs . "$state_file")"
    fi
    return
  fi
  if [[ -z "$state_text" ]]; then
    echo "Error: provide --state or --state-file." >&2
    usage
  fi
  STATE_JSON="$(jq -nc --arg s "$state_text" '$s')"
}

###############################################################################
# POST with backoff on 429/529, honoring retry-after when the API sends one.
###############################################################################
api_post() {
  local body="$1"
  local attempt=1 delay=1
  local body_file hdr_file status retry_after

  body_file="$(mktemp)"
  hdr_file="$(mktemp)"
  trap 'rm -f "$body_file" "$hdr_file"' RETURN

  while :; do
    status="$(printf '%s' "$body" | curl -sS \
      -o "$body_file" -D "$hdr_file" -w '%{http_code}' \
      --connect-timeout 10 --max-time 120 \
      -X POST "$API_URL" \
      -H "Authorization: Bearer ${TYPESAFE_API_KEY}" \
      -H "Content-Type: application/json" \
      --data-binary @-)" || {
        echo "Error: request to TypeSafe failed (network or TLS)." >&2
        exit 1
      }

    case "$status" in
      200)
        RESPONSE="$(cat "$body_file")"
        return 0
        ;;
      401)
        echo "Error: TypeSafe rejected the API key (401). Check TYPESAFE_API_KEY." >&2
        exit 1
        ;;
      400|422)
        echo "Error: TypeSafe rejected the request as invalid ($status)." >&2
        jq . "$body_file" >&2 2>/dev/null || { cat "$body_file" >&2; echo >&2; }
        exit 1
        ;;
      429|529)
        if [[ "$attempt" -ge "$MAX_ATTEMPTS" ]]; then
          echo "Error: TypeSafe returned $status after ${MAX_ATTEMPTS} attempts. Try again shortly." >&2
          exit 1
        fi
        retry_after="$(grep -i '^retry-after:' "$hdr_file" | tr -d '\r' | awk '{print $2}' | head -1)"
        if [[ -n "$retry_after" && "$retry_after" =~ ^[0-9]+$ ]]; then
          sleep "$retry_after"
        else
          sleep "$delay"
          delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
        ;;
      *)
        echo "Error: TypeSafe returned HTTP $status." >&2
        cat "$body_file" >&2
        echo >&2
        exit 1
        ;;
    esac
  done
}

###############################################################################
# Render answers compactly. Probabilities are rounded to 3 places for reading;
# use --raw when you need the full precision.
###############################################################################
format_answers() {
  local response="$1"
  printf '%s\n' "$response" | jq -r '"model=\(.model) input_tokens=\(.usage.input_tokens)"' >&2
  printf '%s\n' "$response" | jq -r '
    def r: (. * 1000 | round) / 1000;
    .answers | to_entries[]
    | .key as $k | .value as $v
    | if   $v.type == "noul"   then "\($k): \($v.noul | r)"
      elif $v.type == "choice" then "\($k): \($v.choice) (p=\($v.probabilities[$v.choice] | r), conf=\($v.confidence | r))"
      elif $v.type == "score"  then "\($k): \($v.score | r) [\($v.legend[($v.score | round | tostring)] // "?")] (conf=\($v.confidence | r))"
      else "\($k): \($v | tojson)" end'
}

emit() {
  local response="$1"
  if [[ "$raw" -eq 1 ]]; then
    printf '%s\n' "$response" | jq .
  else
    format_answers "$response"
  fi
}

resolve_key

case "$cmd" in
  ask)
    if [[ -z "$questions_file" ]]; then
      echo "Error: --questions is required for 'ask'." >&2
      usage
    fi
    if [[ ! -r "$questions_file" ]]; then
      echo "Error: cannot read questions file: $questions_file" >&2
      exit 1
    fi
    if ! jq -e 'type == "object" and (length > 0)' "$questions_file" >/dev/null 2>&1; then
      echo "Error: $questions_file must be a JSON object mapping question ids to question objects." >&2
      exit 1
    fi
    build_state
    questions_json="$(jq -c . "$questions_file")"
    request="$(jq -nc \
      --argjson state "$STATE_JSON" \
      --argjson questions "$questions_json" \
      --arg model "$model" \
      '{state: $state, model: $model, questions: $questions}')"
    api_post "$request"
    emit "$RESPONSE"
    ;;

  noul)
    if [[ -z "$question_text" ]]; then
      echo "Error: --question is required for 'noul'." >&2
      usage
    fi
    build_state
    question_json="$(jq -nc \
      --arg instructions "$question_text" \
      --arg t "$true_desc" \
      --arg f "$false_desc" \
      '{type: "noul", instructions: $instructions}
       + (if ($t | length) > 0 or ($f | length) > 0
          then {criteria: ({} + (if ($t|length) > 0 then {"true": $t} else {} end)
                              + (if ($f|length) > 0 then {"false": $f} else {} end))}
          else {} end)')"
    request="$(jq -nc \
      --argjson state "$STATE_JSON" \
      --argjson q "$question_json" \
      --arg model "$model" \
      '{state: $state, model: $model, questions: {answer: $q}}')"
    api_post "$request"
    emit "$RESPONSE"
    ;;

  check)
    request="$(jq -nc --arg model "$model" '{
      state: "The payout has been failing for three days and I need this fixed now.",
      model: $model,
      questions: {
        is_urgent: {
          type: "noul",
          instructions: "Does this message convey urgency?",
          criteria: { "true": "Explicitly time-sensitive.", "false": "No urgency expressed." }
        }
      }
    }')"
    api_post "$request"
    printf '%s\n' "$RESPONSE" | jq -r '"ok — model=\(.model) is_urgent=\(.answers.is_urgent.noul) input_tokens=\(.usage.input_tokens)"'
    ;;
esac
