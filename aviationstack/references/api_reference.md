# AviationStack API Reference

Base URL: `https://api.aviationstack.com/v1`

## Authentication

All requests require an `access_key` query parameter:
`?access_key=YOUR_API_KEY`

## Endpoints

### Flights (`/v1/flights`)

Track real-time flights or look up historical data (last 3 months).

**Key Parameters:**
- `flight_iata` / `flight_icao`: Specific flight code (e.g., `AA100` / `AAL100`)
- `airline_iata` / `airline_icao`: All flights for an airline
- `dep_iata` / `arr_iata`: Departure or arrival airport
- `flight_status`: `scheduled`, `active`, `landed`, `cancelled`, `incident`, `diverted`
- `flight_date`: `YYYY-MM-DD` (for historical data)
- `limit`: Number of results (default 10, max 100)

**Response Objects:**
- `pagination`: `limit`, `offset`, `count`, `total`
- `data[]`:
  - `flight_date`, `flight_status`
  - `departure`: `airport`, `timezone`, `iata`, `icao`, `terminal`, `gate`, `delay`, `scheduled`, `estimated`, `actual`
  - `arrival`: Same as departure + `baggage`
  - `airline`: `name`, `iata`, `icao`
  - `flight`: `number`, `iata`, `icao`
  - `live`: `updated`, `latitude`, `longitude`, `altitude`, `direction`, `speed_horizontal`, `is_ground`

---

### Airports (`/v1/airports`)

Look up global airport information.

**Key Parameters:**
- `search`: IATA/ICAO code or name (Basic Plan+ for autocomplete)
- `limit`, `offset`

**Response Fields:**
- `airport_name`, `iata_code`, `icao_code`
- `latitude`, `longitude`
- `timezone`, `gmt`, `country_name`, `city_iata_code`

---

### Airlines (`/v1/airlines`)

Look up global airline information.

**Key Parameters:**
- `search`: Name or code
- `limit`, `offset`

**Response Fields:**
- `airline_name`, `iata_code`, `icao_code`, `callsign`
- `hub_code`, `country_name`, `fleet_size`, `status`, `type`, `date_founded`

---

## Errors

Error responses use this JSON format:
```json
{
  "error": {
    "code": "usage_limit_reached",
    "message": "You have reached your monthly usage limit..."
  }
}
```

Common Codes: `invalid_access_key`, `usage_limit_reached`, `rate_limit_reached`, `validation_error`.

## Plan Limitations

- **Free Plan**: HTTPS supported. Access to `/flights`, `/airports`, `/airlines`, `/airplanes`.
- **Basic Plan+**: Access to `/routes`, `/flightsSchedules`, `/flightsFutureSchedules`, and Autocomplete search.
