---
name: flightstatus
description: >-
  Look up real-time flight status, track flights, check airport delays, and
  query departures/arrivals using FlightAware AeroAPI (primary) with
  AviationStack as fallback. Use when a user asks about flight status, delays,
  gate/terminal info, departures/arrivals at an airport, route info, or
  anything related to commercial aviation flight tracking. Requires
  FLIGHTAWARE_API_KEY env var (preferred) or AVIATIONSTACK_API_KEY (fallback).
homepage: https://www.flightaware.com/aeroapi/portal/documentation
metadata:
  {
    "openclaw":
      {
        "emoji": "✈️",
        "requires":
          {
            "bins": ["curl", "jq"],
            "env": ["FLIGHTAWARE_API_KEY"],
            "env_optional": ["AVIATIONSTACK_API_KEY"],
          },
        "primaryEnv": "FLIGHTAWARE_API_KEY",
      },
  }
---

# Flight Status

> Real-time flight tracking powered by FlightAware AeroAPI, with AviationStack as automatic fallback.

## Quick Start

Look up a specific flight by IATA or ICAO code:
```bash
{baseDir}/scripts/flight_status.sh flight AA100
```

Check airport info and delays:
```bash
{baseDir}/scripts/flight_status.sh airport JFK
```

## Usage

### Subcommands

| Subcommand | Description | Example |
|---|---|---|
| `flight <IDENT>` | Status for a specific flight | `flight AA100`, `flight UAL235`, `flight N12345` |
| `airport <CODE>` | Airport info + current delays | `airport JFK`, `airport KJFK` |
| `departures <CODE>` | Upcoming departures from airport | `departures LAX` |
| `arrivals <CODE>` | Upcoming arrivals at airport | `arrivals ORD` |
| `route <ORIG> <DEST>` | Flights between two airports | `route JFK LAX` |

### Flags

| Flag | Description |
|---|---|
| `--raw` | Output raw JSON response from the API |
| `--fallback` | Force use of AviationStack (skip FlightAware) |

### Flight Ident Formats

The script accepts multiple ident formats for the `flight` subcommand:
- **IATA code**: `AA100`, `UA235`, `DL400` — automatically converted to ICAO for FlightAware
- **ICAO code**: `AAL100`, `UAL235`, `DAL400` — used directly
- **Registration**: `N12345` — used directly

### Data Sources

| Source | Key | Capabilities |
|---|---|---|
| **FlightAware AeroAPI** (primary) | `FLIGHTAWARE_API_KEY` | Full flight status, OOOI times, gate/terminal, delays, airport info, departures, arrivals, routes |
| **AviationStack** (fallback) | `AVIATIONSTACK_API_KEY` | Basic flight status lookup only (free tier) |

If FlightAware is unavailable or errors, the script automatically falls back to AviationStack for the `flight` subcommand. The `airport`, `departures`, `arrivals`, and `route` subcommands require FlightAware.

## Examples

### Track a specific flight
```bash
{baseDir}/scripts/flight_status.sh flight AA100
```

Output:
```
✈️  AA100 / AAL100 (American Airlines)
    Status:    En Route
    From:      John F Kennedy Intl (JFK) Terminal 8, Gate 42
    To:        Los Angeles Intl (LAX) Terminal 4, Gate 47B
    Departure: 2026-03-06 08:00 EST (sched) → 2026-03-06 08:25 EST
    Arrival:   2026-03-06 11:30 PST (sched) → 2026-03-06 12:05 PST
    Delay:     25 min dep / 35 min arr
    Aircraft:  B772 / N799AN
    Source:    FlightAware
```

### Check airport delays
```bash
{baseDir}/scripts/flight_status.sh airport KJFK
```

### View departures from an airport
```bash
{baseDir}/scripts/flight_status.sh departures ORD
```

### View arrivals at an airport
```bash
{baseDir}/scripts/flight_status.sh arrivals LAX
```

### Look up flights on a route
```bash
{baseDir}/scripts/flight_status.sh route JFK LAX
```

### Get raw JSON (for custom processing)
```bash
{baseDir}/scripts/flight_status.sh flight UA900 --raw | jq '.flights[0].status'
```

### Force AviationStack fallback
```bash
{baseDir}/scripts/flight_status.sh flight AA100 --fallback
```

## Direct API Access

### FlightAware AeroAPI
```bash
curl -s -H "x-apikey: $FLIGHTAWARE_API_KEY" \
  "https://aeroapi.flightaware.com/aeroapi/flights/AAL100" | jq '.flights[0]'
```

### AviationStack (fallback)
```bash
curl -s "https://api.aviationstack.com/v1/flights?access_key=$AVIATIONSTACK_API_KEY&flight_iata=AA100" | jq '.data[0]'
```

> [!NOTE]
> FlightAware recommends using ICAO idents (e.g. `AAL100`) rather than IATA (e.g. `AA100`) to avoid ambiguity. The script handles this conversion automatically.

> [!WARNING]
> AviationStack free tier has significant limitations: no filtering, no historical data, and delay data may be stale or missing. FlightAware is strongly recommended as the primary data source.
