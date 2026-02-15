---
name: aviationstack
description: >-
  Look up real-time flight status, track flights, and query airport/airline info
  using the AviationStack API. Use when a user asks about flight status, delays,
  gate/terminal info, departures/arrivals at an airport, airline details, or
  anything related to commercial aviation flight tracking. Requires
  AVIATIONSTACK_API_KEY env var.
homepage: https://aviationstack.com/documentation
metadata:
  {
    "openclaw":
      {
        "emoji": "✈️",
        "requires": { "bins": ["curl", "jq"], "env": ["AVIATIONSTACK_API_KEY"] },
        "primaryEnv": "AVIATIONSTACK_API_KEY",
      },
  }
---

# AviationStack

Real-time flight tracking and aviation data via AviationStack API.

## Quick Start

Look up a specific flight (IATA code):
```bash
{baseDir}/scripts/flight_status.sh flight AA100
```

Look up flights by route (departure/arrival airports):
```bash
{baseDir}/scripts/flight_status.sh route JFK LAX
```

Look up airport information:
```bash
{baseDir}/scripts/flight_status.sh airport DEN
```

## Usage

### Subcommands

- `flight <IATA>` — Get status for a specific flight (e.g., AA100, UA235).
- `route <DEP> <ARR>` — List flights between two airports by IATA code.
- `airport <IATA>` — Look up details for an airport.
- `airline <IATA>` — Look up details for an airline (IATA code or Name).
- `active` — List currently airborne flights (use with `--dep` or `--arr` to filter).

### Flags

- `--status <STATUS>` — Filter by: `scheduled`, `active`, `landed`, `cancelled`, `diverted`.
- `--date <YYYY-MM-DD>` — Historical or future flight date.
- `--limit <N>` — Limit results (default 5, max 100).
- `--dep <IATA>` / `--arr <IATA>` — Filter departures or arrivals for the `active` subcommand.
- `--raw` — Output raw JSON response from the API.

## Direct API Access

If you need a specific field not provided by the script's summary:
```bash
curl -s "https://api.aviationstack.com/v1/flights?access_key=$AVIATIONSTACK_API_KEY&flight_iata=AA100" | jq '.data[0]'
```

> [!NOTE]
> For more details on parameters and response data, see [api_reference.md](references/api_reference.md).
