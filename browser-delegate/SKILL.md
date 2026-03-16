---
name: browser-delegate
description: >-
  Delegate tasks that require a real browser to the sandboxed browser agent.
  Use when a page needs JavaScript execution, DOM interaction, navigation,
  screenshots, PDFs, login flows, or content that does not exist in static
  HTML. Prefer web_fetch or web_search for simple static pages.
---

# Browser Delegate

Use this skill to keep the main conversation feeling like a single agent while routing browser-required work into the dedicated sandboxed `browser` agent.

## Trigger

Use this skill when any of the following are true:

- The task needs a real browser session rather than `web_fetch`.
- The site renders data client-side or requires JavaScript.
- You need to click, type, sign in, expand UI, switch tabs, or navigate.
- The user wants a screenshot, PDF, or content extracted from the rendered DOM.
- Static fetch/search results are incomplete, misleading, or blocked.

Do not use this skill for simple static pages. Prefer `web_fetch` or `web_search` first when the page content is available without browser execution.

## Workflow

1. Decide whether the task actually needs a real browser.
2. If yes, verify the `browser` agent is available for subagent spawning.
3. Spawn the sandboxed browser session.
4. Send the concrete browser task.
5. Wait for the browser agent's final extracted result.
6. Return the result to the user in your own voice without exposing subagent plumbing unless it matters.

## Spawn Contract

Use `sessions_spawn` from the main agent side, not from inside the browser agent.

**Important:** Use `runtime: "subagent"` — the browser agent is defined locally in `agents.list`, not as an ACP harness.

Recommended shape:

```json
{
  "runtime": "subagent",
  "agentId": "browser",
  "task": "<structured browser task — include objective, URLs, required actions, return format, and constraints>",
  "label": "browser-delegate",
  "sandbox": "require",
  "cleanup": "keep",
  "mode": "run",
  "runTimeoutSeconds": 300
}
```

Notes:

- `runtime: "subagent"` — required; the browser agent is a local agent, not an ACP harness.
- `sandbox: "require"` ensures the child stays inside the Docker sandbox.
- `cleanup: "keep"` makes follow-up inspection easier if the first handoff fails.
- `mode: "run"` — one-shot execution. The browser agent completes the task and returns.
- Put the full task directly in `task` — no need for a separate `sessions_send` follow-up for simple jobs.
- For multi-step workflows, spawn first with a standing task, then use `sessions_send` for each step.

## Task Template

Use this structured template for the `task` field in `sessions_spawn` (or in `sessions_send` for multi-step flows):

```text
You are the dedicated browser agent.

Objective:
- {what needs to be learned or done}

URLs or starting points:
- {url list}

Required actions:
- Navigate as needed
- Execute JavaScript-backed flows if needed
- Interact with the page only as much as required

Return format:
- Summary: short answer first
- Extracted results: exact facts, values, or steps requested
- Evidence: URLs, page titles, or visible labels that support the answer
- Open questions: anything blocked, ambiguous, or requiring user input

Constraints:
- Do not browse beyond what is needed for this task
- Prefer concise extraction over long narration
- If login, consent, CAPTCHA, or payment is required, stop and say so clearly
```

## Multi-Step Send Contract

For multi-step workflows where you need to send follow-up instructions to an already-running browser session, use `sessions_send`:

```json
{
  "sessionKey": "<spawned-browser-session>",
  "message": "<next step instructions>",
  "timeoutSeconds": 180
}
```

For simple one-shot tasks (most cases), put the full structured task in `sessions_spawn.task` directly — no `sessions_send` needed.

## Response Policy

After the browser agent replies:

- Extract the result the user actually asked for.
- Remove subagent-only chatter, repeated reasoning, and transport details.
- Preserve uncertainty if the browser agent reported ambiguity or blockers.
- Mention the browser step only when it helps explain timing, limits, or confidence.

The user should experience a normal answer from the main agent, not a handoff transcript.

## Failure Handling

- If `sessions_spawn` fails (e.g., `agentId is not allowed`, Docker unavailable, or agent not found), say that sandboxed browser delegation is currently unavailable and fall back only if a static fetch can answer safely.
- If `sessions_send` times out, check subagent status or retry with a narrower task.
- If the browser agent reports login/CAPTCHA/paywall blockers, surface that directly and ask for the minimum needed input.
- If the task turns out to be static after all, stop using the browser agent and answer from `web_fetch`/`web_search` instead.

## Single-Agent Feel

This skill is optimized for a conversational illusion: the main agent remains the interface, while the sandboxed browser agent acts like an internal specialist.

Current runtime limitation:

- `sessions_spawn` posts its own announce/update flow, so the experience may still expose some subagent mechanics.

If you are modifying the deployment to tighten that UX, read [references/implementation-plan.md](references/implementation-plan.md).