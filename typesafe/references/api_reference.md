# TypeSafe System One API Reference

Base URL: `https://api.typesafe.ai/v1`
Docs: https://docs.typesafe.ai

All models are served by the same endpoint. The `model` field selects which one answers.

## Authentication

```
Authorization: Bearer $TYPESAFE_API_KEY
Content-Type: application/json
```

## POST /v1/systemone

### Request

| Field | Type | Required | Description |
|---|---|---|---|
| `state` | string \| object \| array | yes | The content to evaluate. Ingested once, evaluated against every question in parallel. |
| `model` | string | yes | `jev-latest`, `jev-preview`, or a pinned id like `jev-1.13.0`. |
| `questions` | map<string, Question> | yes | Question id → question object. Ids come back as the answer keys. |

Every question object carries `type` and `instructions`. `criteria` is required for `choice` and
`score`, optional for `noul`.

#### `noul` — yes/no

```json
{
  "type": "noul",
  "instructions": "Does this convey urgency?",
  "criteria": {
    "true": "Explicitly time-sensitive",
    "false": "No urgency expressed"
  }
}
```

#### `choice` — one of a known, unordered set

```json
{
  "type": "choice",
  "instructions": "Which team should handle this?",
  "criteria": {
    "billing": "Payments, invoicing, refunds",
    "technical": "Bugs, outages, integrations",
    "sales": "Pricing, upgrades, new accounts"
  }
}
```

#### `score` — position on an ordered spectrum

```json
{
  "type": "score",
  "instructions": "How frustrated is the customer?",
  "criteria": ["Calm", "Frustrated", "Very angry"]
}
```

### Complete request

```json
{
  "state": "Help! My payouts have been failing for 3 days.",
  "model": "jev-latest",
  "questions": {
    "is_urgent": {
      "type": "noul",
      "instructions": "Does this convey urgency?",
      "criteria": {
        "true": "Explicitly time-sensitive",
        "false": "No urgency expressed"
      }
    }
  }
}
```

### Response

| Field | Type | Description |
|---|---|---|
| `model` | string | The versioned id that actually answered (e.g. `jev-1.13.0`). Log this. |
| `answers` | map<string, Answer> | Keyed by the question ids from the request. |
| `usage` | object | `input_tokens`, `output_tokens`. |

#### Answer shapes

```json
{ "type": "noul", "noul": 0.95 }
```

```json
{
  "type": "choice",
  "choice": "billing",
  "probabilities": { "billing": 0.88, "technical": 0.12, "sales": 0.0 },
  "confidence": 0.81
}
```

```json
{
  "type": "score",
  "score": 1.05,
  "legend": { "0": "Calm", "1": "Frustrated", "2": "Very angry" },
  "probabilities": { "0": 0.0, "1": 0.95, "2": 0.05 },
  "confidence": 0.92
}
```

### Complete response

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "is_urgent": { "type": "noul", "noul": 0.95 }
  },
  "usage": { "input_tokens": 307, "output_tokens": 20 }
}
```

## Errors

| Status | Meaning | Handling |
|---|---|---|
| 401 | Invalid or missing API key | Fail. Do not retry. |
| 422 | Validation failure — malformed request | Fail. Fix the request shape. |
| 429 | Rate limit exceeded | Retry with backoff, honor `retry-after`. |
| 529 | Service overloaded | Retry with backoff. |

`jev.sh` implements the retry policy: up to 3 attempts, `retry-after` when present, otherwise
exponential backoff from 1s.

## Models

| Model | Price (per Btok / per Mtok) | Rate limits | Context |
|---|---|---|---|
| `jev-1.13.0` | $42 / $0.042 | 250,000 tok/sec, 1,200 req/min | 64k per request; 32k for `state` + longest question |

Input tokens are charged; **output tokens are free**. Rate limits adjust dynamically and can change
without notice.

### Aliases

| Alias | Points to | Meaning |
|---|---|---|
| `jev-latest` | `jev-1.13.0` | Most recent stable release. SDK default. |
| `jev-preview` | `jev-1.13.0` | Most recent release, stable or not. |

An alias moves when a new release ships, so answers behind it can change with no change on your side.
Pin the versioned id once thresholds are tuned.

## Input

Text only — string, JSON object, or array of text values. No image, audio, or video. Pre-process
non-text inputs into text or structured fields before sending them as `state`.

When `state` is an object, questions can reference its fields by name in `instructions`, using
backticks: ``"Does `ticket_message` request a refund?"``

## Customization

Jev is not fine-tuned or LoRA-adapted per account; the same weights serve everyone. Domain fit comes
from the request:

1. Proprietary content, records, and reference material go in `state`.
2. Domain rules and boundary cases go in each question's `instructions` and `criteria`.
3. Broad judgements get decomposed into atomic questions and recombined in code.

## Client SDKs

Python and JavaScript SDKs exist (`client.system_one(state=..., questions={...})`) with retry and
backoff built in. This skill uses the HTTP API directly to avoid adding a runtime dependency to the
gateway.
