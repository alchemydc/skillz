# Flight Status API Reference

## FlightAware AeroAPI (Primary)

Base URL: `https://aeroapi.flightaware.com/aeroapi`
Docs: https://www.flightaware.com/aeroapi/portal/documentation

### Authentication

Set `x-apikey` header with your API key:
```
x-apikey: YOUR_FLIGHTAWARE_API_KEY
```

### Key Endpoints Used

#### GET /flights/{ident}
Flight info status summary. Returns ~14 days of recent and scheduled flights.

**Path params:**
- `ident` — ICAO designator (e.g. `UAL4`), registration (e.g. `N123HQ`), or `fa_flight_id`

**Query params:**
- `ident_type` — `designator`, `registration`, or `fa_flight_id`
- `start` / `end` — ISO8601 date range (up to 10 days past, 2 days future)
- `max_pages` — default 1

**Response fields per flight:**
- `ident`, `ident_icao`, `ident_iata`, `fa_flight_id`
- `operator`, `operator_icao`, `operator_iata`, `flight_number`
- `registration`, `aircraft_type`
- `scheduled_out`, `estimated_out`, `actual_out` — gate departure times
- `scheduled_off`, `estimated_off`, `actual_off` — runway departure times
- `scheduled_on`, `estimated_on`, `actual_on` — runway arrival times
- `scheduled_in`, `estimated_in`, `actual_in` — gate arrival times
- `gate_origin`, `gate_destination`, `terminal_origin`, `terminal_destination`
- `baggage_claim`
- `cancelled` (bool), `diverted` (bool)
- `status` — human-readable status string
- `origin` / `destination` — objects with `code`, `code_icao`, `code_iata`, `name`, `city`, `timezone`
- `last_position` — latest position with lat/lon/alt/speed/heading

#### GET /airports/{id}
Static airport information.

**Response:** `name`, `code_icao`, `code_iata`, `city`, `state`, `timezone`, `elevation`, `latitude`, `longitude`

#### GET /airports/{id}/delays
Airport delay information with reason codes.

**Response:** `category`, `color`, `delay_secs`, `reasons[]`

#### GET /airports/{id}/flights/scheduled_departures
Upcoming departures ordered by estimated_off ascending.

#### GET /airports/{id}/flights/scheduled_arrivals
Upcoming arrivals ordered by estimated_on ascending.

#### GET /airports/{id}/flights/to/{dest_id}
Flights between two airports (nonstop + one-stop). Returns `flights[].segments[]`.

### OOOI Times (FlightAware convention)
- **Out**: Gate departure (`scheduled_out` / `actual_out`)
- **Off**: Wheels off runway (`scheduled_off` / `actual_off`)
- **On**: Wheels on runway (`scheduled_on` / `actual_on`)
- **In**: Gate arrival (`scheduled_in` / `actual_in`)

### Error Format
```json
{
  "title": "Error Title",
  "reason": "Detailed reason",
  "detail": "Additional details",
  "status": 400
}
```

---

## AviationStack (Fallback)

Base URL: `https://api.aviationstack.com/v1`
Docs: https://aviationstack.com/documentation

### Authentication
Query parameter: `?access_key=YOUR_API_KEY`

### Key Endpoint Used

#### GET /v1/flights
- `flight_iata` — e.g. `AA100`

**Response fields per flight (`.data[]`):**
- `flight_date`, `flight_status`
- `departure` / `arrival` — `.airport`, `.iata`, `.timezone`, `.terminal`, `.gate`, `.delay`, `.scheduled`, `.estimated`, `.actual`
- `airline` — `.name`, `.iata`
- `flight` — `.iata`, `.icao`

### Free Tier Limitations
- Only `/flights` endpoint with basic lookup
- No filtering by status, date, limit
- No `/routes`, `/airports` (metadata), `/airlines` detail
- Timestamps have bogus `+00:00` offset (local time mislabeled as UTC)
