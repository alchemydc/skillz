# agent-browser — Deployment & Configuration Guide

This skill requires manual installation and openclaw configuration before first use. Follow all steps below on a new machine.

## Step 1 — Install agent-browser and Chrome

```bash
# Install the CLI globally via npm
npm install -g agent-browser

# Download Chrome for Testing + system dependencies
# --with-deps requires sudo (runs sudo apt-get / sudo dnf)
agent-browser install --with-deps

# Verify
agent-browser --version
agent-browser open https://example.com && agent-browser snapshot -i && agent-browser close
```

> **Linux note:** `--with-deps` installs a large set of shared libraries Chrome requires (libX11, libglib, NSS, fonts, etc.) and requires `sudo`. If the openclaw user cannot run `sudo apt-get`, use a second account with sudo to run `agent-browser install --with-deps`, or check whether a prior Chromium/Chrome install on the machine already satisfies the deps — in which case `agent-browser install` alone may be sufficient.

> **Updates:** Run `agent-browser upgrade` periodically. It auto-detects the install method (npm) and runs `npm update -g agent-browser`.

## Step 2 — Create the native security config

Create `~/.agent-browser/config.json` (applies to all agent-browser invocations):

```json
{
  "contentBoundaries": true,
  "maxOutput": 50000,
  "confirmActions": "eval,download",
  "idleTimeoutMs": 120000,
  "allowedDomains": []
}
```

| Key | Purpose |
|-----|---------|
| `contentBoundaries` | Wraps all page output in a nonce-delimited boundary to prevent prompt injection from page content reaching the agent as instructions |
| `maxOutput` | Caps snapshot/text output at 50 000 chars to prevent context flooding |
| `confirmActions` | Gates JavaScript `eval` and file `download` actions, requiring explicit agent confirmation |
| `idleTimeoutMs` | Auto-shuts the browser daemon after 2 minutes of inactivity; prevents orphaned Chrome processes |
| `allowedDomains` | Domains the browser may navigate to (empty = unrestricted). A reference template is in `agent-browser.json` in this directory |

## Step 3 — Update openclaw.json

Three changes are required in `~/.openclaw/openclaw.json`.

### a) Add `agent-browser` to `tools.exec.safeBins`

```json
"safeBins": [
  "agent-browser",
  ...existing entries...
]
```

### b) Add a `safeBinProfile` under `tools.exec.safeBinProfiles`

```json
"agent-browser": {
  "maxPositional": 4,
  "deniedFlags": ["--allow-file-access"]
}
```

The `--allow-file-access` flag would allow Chrome to read arbitrary local files — denying it closes that attack surface.

### c) Remove any existing Docker browser agent

If your config has a `browser` agent in `agents.list` with Docker sandbox and `browser` tool, remove the entire agent object — it conflicts with this skill's direct-exec model. Also rename or remove `~/.openclaw/workspace/skills/browser-delegate/` if present; that skill was purpose-built to spawn the Docker browser agent.

## Step 4 — (Optional) Enable domain allowlist

When you know which sites the agent will browse, restrict navigation by populating `allowedDomains` in `~/.agent-browser/config.json`. Wildcards are supported and also match the bare domain:

```json
"allowedDomains": ["github.com", "*.github.com", "docs.example.com"]
```

Sub-resource requests (scripts, images, fetch calls) and WebSocket connections to non-allowed domains are also blocked.

## Step 5 — (Optional) Enable action policy

An action policy file provides rule-based control over which browser actions are permitted. A conservative template is in `action-policy.json` in this directory.

To activate:

```bash
cp ~/.openclaw/workspace/skills/agent-browser/references/action-policy.json \
   ~/.agent-browser/action-policy.json
```

Then add to `~/.agent-browser/config.json`:

```json
"actionPolicy": "~/.agent-browser/action-policy.json"
```
