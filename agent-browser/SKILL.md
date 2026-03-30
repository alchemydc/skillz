---
name: agent-browser
description: >-
  Headless browser automation via the agent-browser CLI. Use when: (1) a page
  requires JavaScript execution or client-side rendering, (2) you need to click,
  fill forms, navigate, sign in, or interact with UI elements, (3) taking
  screenshots or generating PDFs, (4) extracting content from the rendered DOM.
  Prefer web_fetch or web_search for simple static pages — only invoke this
  skill when the browser is genuinely needed.
metadata:
  {
    "openclaw":
      {
        "emoji": "🌐",
        "requires": { "bins": ["agent-browser"] },
        "install":
          [
            {
              "id": "npm",
              "kind": "node",
              "package": "agent-browser",
              "bins": ["agent-browser"],
              "label": "Install agent-browser (npm)",
            },
          ],
      },
  }
---

# agent-browser

Use the `agent-browser` CLI to control a headless Chrome browser directly from the main agent via `exec`. No subagent or Docker sandbox required.

> **New deployment?** See `references/setup.md` for installation and openclaw configuration instructions.

## When to Use

✅ **USE this skill when:**

- The page renders data client-side or requires JavaScript
- The task requires clicking, typing, signing in, expanding UI, or navigating
- The user wants a screenshot, PDF, or content extracted from the rendered DOM
- `web_fetch` or `web_search` returned incomplete, blocked, or stale results

❌ **Do NOT use when:**

- Simple static HTML is available — use `web_fetch` first
- The task only needs a URL fetched with no interaction
- The full target is an API endpoint (use `web_fetch` or `exec curl`)

## Core Workflow

The key pattern is **snapshot → ref → interact**. Refs from a snapshot are deterministic and fast; always re-snapshot after navigation or significant page changes.

```bash
# 1. Navigate to the page
agent-browser open https://example.com

# 2. Get interactive elements with refs — use --json for machine-readable output
agent-browser snapshot -i --json

# Example snapshot output (refs like @e1, @e2):
# {"success":true,"data":{"snapshot":"- button \"Sign In\" [ref=e1]\n- textbox \"Email\" [ref=e2]\n..."}}

# 3. Interact using refs
agent-browser fill @e2 "user@example.com"
agent-browser fill @e3 "mypassword"
agent-browser click @e1

# 4. Re-snapshot after page changes
agent-browser snapshot -i --json

# 5. Capture result if needed
agent-browser screenshot /tmp/result.png

# 6. Always close when done
agent-browser close
```

## Snapshot Options

```bash
agent-browser snapshot          # Full accessibility tree
agent-browser snapshot -i       # Interactive elements only (best for agent use)
agent-browser snapshot -i -c    # Compact: remove empty structural elements
agent-browser snapshot -i -d 4  # Limit tree depth
agent-browser snapshot -i -s "#main"  # Scope to a CSS selector
```

## Element Interaction

```bash
# Click
agent-browser click @e1
agent-browser click "#submit-button"
agent-browser find role button click --name "Submit"

# Fill / type
agent-browser fill @e2 "text"          # Clear then fill
agent-browser type @e2 "text"          # Append keystrokes
agent-browser press Enter              # Keyboard key

# Wait for content before acting
agent-browser wait @e5                          # Wait for element visible
agent-browser wait --text "Welcome"             # Wait for text to appear
agent-browser wait --load networkidle           # Wait for network idle
agent-browser wait --fn "window.ready === true" # Wait for JS condition
```

## Capture

```bash
agent-browser screenshot /tmp/page.png           # Screenshot (add --full for full page)
agent-browser screenshot --annotate /tmp/page.png # Numbered labels on interactive elements
agent-browser pdf /tmp/doc.pdf                   # Save as PDF
agent-browser get text @e1                       # Get element text
agent-browser get html @e1                       # Get element innerHTML
agent-browser get url                            # Current URL
agent-browser get title                          # Page title
```

## Batch Execution

Use batch mode to avoid per-command startup overhead for multi-step flows:

```bash
echo '[
  ["open", "https://example.com"],
  ["wait", "--load", "networkidle"],
  ["snapshot", "-i", "--json"],
  ["click", "@e1"],
  ["screenshot", "/tmp/result.png"]
]' | agent-browser batch --json
```

## Sessions

Each session has its own browser instance, cookies, storage, and history:

```bash
agent-browser --session task1 open https://site-a.com
agent-browser --session task2 open https://site-b.com
agent-browser session list
agent-browser close --all    # Close all sessions when done
```

## Security

All security features are opt-in. Defaults in `~/.agent-browser/config.json` set `contentBoundaries: true` and `maxOutput: 50000`. Additional hardening:

```bash
# Restrict navigation to specific domains
AGENT_BROWSER_ALLOWED_DOMAINS="example.com,*.example.com" agent-browser open https://example.com

# Gate destructive actions
agent-browser --confirm-actions eval,download open https://example.com

# Content boundary markers prevent prompt injection
agent-browser --content-boundaries snapshot
```

## Advanced / Cloud Providers

For environments where a local Chrome isn't feasible, agent-browser supports cloud providers:

```bash
# Browserless
AGENT_BROWSER_PROVIDER=browserless BROWSERLESS_API_KEY="..." agent-browser open https://example.com

# Browserbase
AGENT_BROWSER_PROVIDER=browserbase BROWSERBASE_API_KEY="..." agent-browser open https://example.com
```

## Troubleshooting

**Chrome fails to launch / missing shared library:**
Run `agent-browser install --with-deps` (requires sudo on Linux) to install system dependencies.

**Element ref not found (@e3):**
Refs are page-scoped. Take a fresh `snapshot -i` after any navigation or dynamic DOM change.

**Command hangs / timeout:**
Default timeout is 25s. Override: `AGENT_BROWSER_DEFAULT_TIMEOUT=45000 agent-browser ...`
Clean up stale daemon: `agent-browser close --all`

**Daemon leftover between sessions:**
Set `AGENT_BROWSER_IDLE_TIMEOUT_MS=60000` in config to auto-shutdown after 1 minute idle.

**Page not fully loaded:**
Add `agent-browser wait --load networkidle` after `open` before snapshotting.

## Agent Prompt

When a user asks for something that requires a real browser, use this skill directly — do not spawn a subagent. Typical workflow:

1. `agent-browser open <url>` — navigate
2. `agent-browser wait --load networkidle` — ensure fully loaded
3. `agent-browser snapshot -i --json` — discover interactive elements and their @refs
4. Interact: `fill @eN "value"`, `click @eN`, `press Enter`
5. Re-snapshot after navigation or dynamic changes
6. Capture with `screenshot` or `pdf` if the user wants visual output
7. `agent-browser close` when done — don't leave browser sessions open

Use `--json` flag on all commands for clean machine-readable output. Prefer `snapshot -i` (interactive only) over full snapshot to keep output size manageable. Always close the browser at the end of the task.
