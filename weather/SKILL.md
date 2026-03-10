---
name: weather
description: "Get current weather and forecasts via wttr.in or Open-Meteo. Use when: user asks about weather, temperature, or forecasts for any location. NOT for: historical weather data, severe weather alerts, or detailed meteorological analysis. No API key needed."
metadata: { "openclaw": { "emoji": "🌤️", "requires": { "bins": ["curl"] } } }
---

# Weather Skill

Get current weather conditions and forecasts.

## When to Use

✅ **USE this skill when:**

- "What's the weather?"
- "Will it rain today/tomorrow?"
- "Temperature in [city]"
- "Weather forecast for the week"
- Travel planning weather checks

## When NOT to Use

❌ **DON'T use this skill when:**

- Historical weather data → use weather archives/APIs
- Climate analysis or trends → use specialized data sources
- Hyper-local microclimate data → use local sensors
- Severe weather alerts → check official NWS sources
- Aviation/marine weather → use specialized services (METAR, etc.)

## Location

Always include a city, region, or airport code in weather queries.

## Reliable wttr.in Requests

Use a small wrapper so transient wttr.in timeouts do not fail the skill immediately.

```bash
wttr_fetch() {
	url="$1"
	attempt=1
	max_attempts=3
	delay_seconds=1

	while [ "$attempt" -le "$max_attempts" ]; do
		if curl -fsS --connect-timeout 5 --max-time 15 "$url"; then
			return 0
		fi

		if [ "$attempt" -eq "$max_attempts" ]; then
			echo "wttr.in request failed after ${max_attempts} attempts: $url" >&2
			echo "Try the same location again in a moment; wttr.in is occasionally slow." >&2
			return 1
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
		delay_seconds=$((delay_seconds * 2))
	done
}
```

- Use `-f` so HTTP errors are treated as failures.
- Use `--connect-timeout 5` to fail fast on stalled connections.
- Use `--max-time 15` to prevent hanging requests.
- Retry up to 3 total attempts with short backoff.

## Commands

### Current Weather

```bash
# One-line summary
wttr_fetch "https://wttr.in/London?format=3"

# Detailed current conditions
wttr_fetch "https://wttr.in/London?0"

# Specific city
wttr_fetch "https://wttr.in/New+York?format=3"
```

### Forecasts

```bash
# 3-day forecast
wttr_fetch "https://wttr.in/London"

# Week forecast
wttr_fetch "https://wttr.in/London?format=v2"

# Specific day (0=today, 1=tomorrow, 2=day after)
wttr_fetch "https://wttr.in/London?1"
```

### Format Options

```bash
# One-liner
wttr_fetch "https://wttr.in/London?format=%l:+%c+%t+%w"

# JSON output
wttr_fetch "https://wttr.in/London?format=j1"

# PNG image
wttr_fetch "https://wttr.in/London.png"
```

### Format Codes

- `%c` — Weather condition emoji
- `%t` — Temperature
- `%f` — "Feels like"
- `%w` — Wind
- `%h` — Humidity
- `%p` — Precipitation
- `%l` — Location

## Quick Responses

**"What's the weather?"**

```bash
wttr_fetch "https://wttr.in/London?format=%l:+%c+%t+(feels+like+%f),+%w+wind,+%h+humidity"
```

**"Will it rain?"**

```bash
wttr_fetch "https://wttr.in/London?format=%l:+%c+%p"
```

**"Weekend forecast"**

```bash
wttr_fetch "https://wttr.in/London?format=v2"
```

## Notes

- No API key needed (uses wttr.in)
- wttr.in format help: https://wttr.in/:help
- Rate limited; don't spam requests
- Works for most global cities
- Supports airport codes: `wttr_fetch "https://wttr.in/ORD"`
- If `wttr_fetch` still fails, tell the user wttr.in timed out and retry once later instead of looping indefinitely
