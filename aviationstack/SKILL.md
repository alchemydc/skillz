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

> [!WARNING]
> **Free Plan Limitations**: This skill uses the AviationStack free tier, which supports only basic flight lookups. Filtering, historical dates, airports, airlines, and route queries are not available without a paid plan upgrade.

Real-time flight tracking via AviationStack API (free tier).

## Quick Start

Look up a specific flight by IATA code:
```bash
{baseDir}/scripts/flight_status.sh flight AA100
```

## Usage

### Subcommands

- `flight <IATA>` — Get status for a specific flight (e.g., AA100, UA235). **Free tier only.**

### Flags

- `--raw` — Output raw JSON response from the API.

> [!CAUTION]
> The following features require a **paid AviationStack plan** and will be rejected:
> - `route` subcommand (requires Basic plan)
> - `airport` subcommand (requires Basic plan)
> - `airline` subcommand (requires Basic plan)
> - `active` subcommand (requires Basic plan)
> - `--status`, `--date`, `--limit`, `--dep`, `--arr` flags (require Basic plan or higher)

## Direct API Access

If you need a specific field not provided by the script's summary:
```bash
curl -s "https://api.aviationstack.com/v1/flights?access_key=$AVIATIONSTACK_API_KEY&flight_iata=AA100" | jq '.data[0]'
```

> [!NOTE]
> For more details on the AviationStack API and plan tiers, see https://aviationstack.com/documentation.
