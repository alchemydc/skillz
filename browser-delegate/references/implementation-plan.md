# Browser Delegate Implementation Plan

Goal: preserve a single-agent user experience in the main session while forcing real-browser work into the dedicated sandboxed `browser` agent.

## Desired Behavior

When the main agent detects browser-only work, it should:

1. Spawn agent `browser`
2. Send the concrete task
3. Wait for the final extracted result
4. Reply to the user as if the main agent completed the task directly

## Current Constraints

- The `browser` agent already exists in `.openclaw/openclaw.json` and is sandboxed in Docker.
- The `browser` agent is intentionally locked down: it can browse, fetch, and search, but cannot spawn or relay to other sessions.
- The main agent must own the delegation step.
- `sessions_spawn` is asynchronous and emits announce traffic, which weakens the single-agent illusion.

## Phase 1: Ship The Skill

Deliver the local workspace skill in `.openclaw/workspace/skills/browser-delegate`.

Contents:

- Clear trigger conditions for when browser delegation is required
- A spawn contract using `sessions_spawn` with `agentId: "browser"`
- A send contract using `sessions_send` with a bounded timeout
- A response policy that tells the main agent to collapse the child result into a normal final answer

Outcome:

- The main agent gets a reusable playbook immediately.
- Browser delegation becomes consistent instead of ad hoc.

## Phase 2: Standardize The Prompt Contract

Keep the handoff prompt structured and boring.

Required sections:

- Objective
- Starting URL(s)
- Required actions
- Return format
- Constraints and stop conditions

Why:

- The browser agent is cheaper and more constrained than main.
- Structured prompts reduce wasted browsing and make the returned payload easier to summarize.

## Phase 3: Reduce Visible Subagent Noise

If you want a stronger single-agent feel, add one of these runtime improvements in OpenClaw itself:

1. Add an internal delegation helper that wraps `sessions_spawn` plus `sessions_send` and suppresses intermediate announce noise.
2. Add a `sessions_spawn` option for silent internal delegation to the parent session.
3. Add a first-class `delegate_browser` tool that always targets `agentId: "browser"` with `sandbox: "require"`.

Recommendation:

- Option 3 is the cleanest operator-facing model.
- Option 1 is the smallest runtime change if you want to prototype quickly.

## Phase 4: Add Safety Guards

Any future runtime helper should enforce:

- hard-coded `agentId: "browser"`
- `sandbox: "require"`
- bounded timeouts
- optional allowlist for domains if you want stricter browsing policy
- output size limits so large DOM dumps do not flood the parent session

## Phase 5: Validate The UX

Test these cases end-to-end:

1. Static page request: main agent answers without browser delegation.
2. JavaScript-rendered page: main agent delegates and returns extracted content.
3. Browser interaction request: click/type/navigation works via the sandboxed agent.
4. Login or CAPTCHA: browser agent stops cleanly and main agent asks for help.
5. Timeout: main agent reports partial failure without leaking internal session details.

## Suggested Next Runtime Work

If you choose to implement runtime support in OpenClaw, inspect these areas first:

- `docs/tools/subagents.md`
- `docs/concepts/session-tool.md`
- `src/agents/tools/sessions-spawn-tool.ts`
- `src/agents/tools/sessions-send-tool.ts`
- `src/agents/tool-catalog.ts`

That is where the current session handoff semantics and tool surface are defined.