---
name: typesafe
description: >-
  Ask Jev (TypeSafe System One) for calibrated yes/no, choice, and score
  judgements about a piece of text. Use when a decision needs judgement that
  regex or parsing handles badly, or when classifying, triaging, routing, or
  rating text would otherwise cost a full model turn: "is this urgent?",
  "which handler owns this?", "how angry is this person?", "does this contain
  PII?". NOT for generating text, answering open questions, summarizing, or
  anything that needs a written response — Jev only returns probabilities.
  Requires TYPESAFE_API_KEY env var.
homepage: https://docs.typesafe.ai
metadata:
  {
    "openclaw":
      {
        "emoji": "⚖️",
        "requires":
          { "bins": ["curl", "jq"], "env": ["TYPESAFE_API_KEY"] },
        "primaryEnv": "TYPESAFE_API_KEY",
      },
  }
---

# TypeSafe / Jev

> Calibrated judgement as a primitive. Jev ingests a `state` once and evaluates every
> question against it in parallel, returning probabilities — never prose.

## Quick Start

One-shot yes/no:
```bash
/home/dc/.openclaw/workspace/skills/typesafe/scripts/jev.sh noul --state "My payouts have been failing for 3 days." --question "Does this message convey urgency?"
```

A committed question set, many questions in one request:
```bash
/home/dc/.openclaw/workspace/skills/typesafe/scripts/jev.sh ask --questions /home/dc/.openclaw/workspace/skills/typesafe/questions/example.json --state "My payouts have been failing for 3 days."
```

Auth and connectivity check:
```bash
/home/dc/.openclaw/workspace/skills/typesafe/scripts/jev.sh check
```

> ⚠️ **Exec policy constraints** — The gateway runs in `security=allowlist` mode. To avoid approval prompts:
> - Always use the full absolute path shown above — never `~` or `{baseDir}`.
> - **Never** append shell redirections (`2>/dev/null`, `>/tmp/out`), pipes (`| jq`), or chaining (`&& echo done`). Redirections and chaining cause the allowlist to reject the command. Use `--raw` instead of piping to `jq`.
> - **Always quote** `--state`, `--question`, `--true`, and `--false` values. An unquoted `?`, `*`, `{`, `[`, or `~` in the text defeats the allowlist, and under cron it fails silently. Question text almost always ends in `?`, so this matters every single call.
> - Pass all options as flags to the script itself. Stderr is already handled internally.

## When to Use

✅ **USE this skill when:**

- A decision is fuzzy and a regex would be brittle: "is this spam?", "is this a refund request?"
- Routing or triage: pick one handler, one category, one owner from a known set.
- Rating along a spectrum: severity, frustration, confidence, risk.
- You want the *probability itself*, not a verdict — so code downstream can threshold on it.
- You would otherwise spend a full expensive-model turn on a one-bit answer.

## When NOT to Use

❌ **DON'T use this skill when:**

- The answer should be prose → just answer normally.
- The question is open-ended or needs reasoning steps → use the main model.
- You need extraction of specific values (dates, names, amounts) → Jev scores, it does not extract.
- The input is an image, audio, or video → pre-process to text first; Jev is text only.
- The decision is a **security control**. Jev is probabilistic. Never let it be the thing standing between a command and execution.

## The Three Question Types

Every question needs an id (the map key), a `type`, and `instructions`. `criteria` is required for
`choice` and `score`, optional for `noul`.

### `noul` — yes/no, returns a probability

```json
{
  "is_urgent": {
    "type": "noul",
    "instructions": "Does this message convey urgency?",
    "criteria": {
      "true": "Explicitly time-sensitive.",
      "false": "No urgency expressed."
    }
  }
}
```
Answer: `{"type": "noul", "noul": 0.95}` — a probability from 0 to 1. **Not a boolean.** 0.95 means
"almost certainly yes"; 0.5 means "no idea". `noul` carries no separate `confidence`, because the
probability already is the confidence.

### `choice` — pick one from a known set

```json
{
  "team": {
    "type": "choice",
    "instructions": "Which team should handle this?",
    "criteria": {
      "billing": "Payments, invoicing, refunds.",
      "technical": "Bugs, outages, integrations.",
      "sales": "Pricing, upgrades, new accounts.",
      "other": "None of the above."
    }
  }
}
```
Answer: `{"choice": "billing", "probabilities": {...}, "confidence": 0.81}`. Always include an
`other` / `none of the above` option — without one, Jev is forced to pick from a set that may not
cover the input.

### `score` — rate along an ordered spectrum

```json
{
  "severity": {
    "type": "score",
    "instructions": "How severe is this issue?",
    "criteria": ["Minor bug.", "Moderate impact.", "Critical, system down."]
  }
}
```
Answer: `{"score": 1.05, "legend": {"0": "...", "1": "...", "2": "..."}, "probabilities": {...}, "confidence": 0.92}`.
The score can land *between* levels — `1.05` means "moderate impact, edging toward critical". Levels
must be genuinely ordered; if they are not, use `choice`.

## Reading the Answers

| Type | Act on | Also returned |
|---|---|---|
| `noul` | the probability directly | — |
| `choice` | `choice`, gated by `confidence` | full `probabilities` distribution |
| `score` | `score`, gated by `confidence` | `legend`, full `probabilities` |

`confidence` summarizes how peaked the distribution is. Use it as a second axis: act automatically
when it is high, escalate to a person when it is low.

A reasonable starting rule, to be tuned against real data rather than trusted as given:

- **≥ 0.85** — act on it.
- **0.5 – 0.85** — act, but say you are unsure, or ask.
- **< 0.5** — treat as unknown; fall back to asking a human.

## Patterns

**Speculative fan-out.** Adding questions barely changes response time and costs only the tokens for
the extra question text, which are cheap. Ask everything you *might* need in one call and let the
code downstream decide what was relevant. `questions/example.json` is built this way: urgency,
human-needed, topic, and frustration in a single request.

**Confidence-gated routing.** Route on `choice`, but send anything below your confidence floor to a
human path instead of the best guess.

**Composite scoring.** Decompose a broad judgement into several atomic questions and combine the
probabilities in code, rather than asking one vague question and hoping.

## Structured State

`state` does not have to be a string. If `--state-file` points at valid JSON, it is sent
structurally, and `instructions` can then reference fields by name:

```json
{
  "refund_ok": {
    "type": "noul",
    "instructions": "Does `ticket_message` describe a situation the `refund_policy` allows a refund for?"
  }
}
```

This is how you give Jev your own policy, records, or reference material — it is not fine-tuned per
account, so everything proprietary rides in the `state` and in the `criteria`.

## Keep Questions in One Place

Committed question sets live in `questions/*.json` in this skill. Put them there rather than
improvising them inline, so that wording and thresholds are reviewable and diffable. Question wording
is load-bearing and worth editing collaboratively with the user — expect to iterate on it.

## Pin the Model When Thresholds Matter

`jev-latest` is an alias and moves when TypeSafe ships a release, which can shift the answers behind
a tuned threshold without any change on your side. Once a threshold has been tuned against real data,
pass `--model jev-1.13.0`. The response's `model` field always reports the versioned id that actually
answered, and the script prints it to stderr.

## Limits and Cost

- 64k tokens per request total; 32k for the `state` plus the single longest question.
- Text only. Pre-process anything else.
- $0.042 per million input tokens; **output tokens are free**. A triage call costs a rounding error.
- Rate limits: 250,000 tokens/sec and 1,200 requests/min, adjusted dynamically. The script retries
  429 and 529 up to 3 times with backoff, honoring `retry-after`.

## Notes

- Full API details: `references/api_reference.md`.
- Docs: https://docs.typesafe.ai — see also `/model-jaggedness/jev-1.13` for known weak spots,
  particularly how accuracy shifts as the state grows.
- English is the primary training language; other languages work less well. Watch `confidence`
  closely on non-English input.
- TypeSafe states it does not train on customer requests or responses.
