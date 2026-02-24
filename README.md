# mcp-chrome-wsl

Setup guide for using **Chrome DevTools MCP** with **Claude Code** on **WSL2** — navigate, screenshot, click & interact with your browser in real time.

## Overview

This guide explains how to connect Claude Code (running in WSL2) to your Windows Chrome browser via the MCP Chrome DevTools server. Once set up, Claude Code can:

- Navigate to any URL (including `localhost` dev servers)
- Take screenshots and accessibility snapshots
- Click buttons, fill forms, interact with the page
- Read console logs and network requests
- Run JavaScript in the browser
- Resize viewport for responsive testing

## Architecture

```
Chrome (Windows) --remote-debugging-port=9222
        ↕ CDP Protocol (via WSL2 NAT gateway IP)
MCP Chrome DevTools Server (WSL2)
        ↕ MCP Protocol
Claude Code (WSL2)
```

## Prerequisites

- Windows 11 with WSL2 (Ubuntu)
- Google Chrome installed on Windows
- Node.js installed in WSL2
- Claude Code installed in WSL2

## Quick Install

```bash
chmod +x install.sh
./install.sh
```

This will:
1. Install `chrome-devtools-mcp` globally
2. Create the WSL2 wrapper script at `~/.local/bin/`
3. Register the MCP server in Claude Code

## Manual Setup

### 1. Install the MCP package

```bash
npm install -g chrome-devtools-mcp@latest
```

### 2. Create the WSL2 wrapper script

The key challenge on WSL2: Chrome runs on Windows, but the MCP server runs in Linux. They can't talk via `localhost` — you need the WSL2 NAT gateway IP. This wrapper resolves it dynamically:

```bash
mkdir -p ~/.local/bin
cp scripts/chrome-devtools-mcp-wrapper.sh ~/.local/bin/
chmod +x ~/.local/bin/chrome-devtools-mcp-wrapper.sh
```

The wrapper ([`scripts/chrome-devtools-mcp-wrapper.sh`](scripts/chrome-devtools-mcp-wrapper.sh)):

```bash
#!/bin/bash
WIN_HOST=$(ip route show default | awk '{print $3}')
exec npx chrome-devtools-mcp@latest --browserUrl "http://${WIN_HOST}:9222" "$@"
```

It grabs the Windows host IP from the default route and passes it as `--browserUrl` to the MCP server.

### 3. Register in Claude Code

```bash
claude mcp add chrome-devtools -s user -- bash ~/.local/bin/chrome-devtools-mcp-wrapper.sh
```

This adds the following config to your `~/.claude.json` (see [`config/mcp-server.json`](config/mcp-server.json) for reference):

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "type": "stdio",
      "command": "bash",
      "args": [
        "/home/<YOUR_USER>/.local/bin/chrome-devtools-mcp-wrapper.sh"
      ],
      "env": {}
    }
  }
}
```

### 4. Launch Chrome with remote debugging

**Important:** Close ALL Chrome instances first (check Task Manager), then relaunch with the debugging flag.

```bash
"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" --remote-debugging-port=9222
```

Or use the provided script:

```bash
chmod +x scripts/launch-chrome.sh
./scripts/launch-chrome.sh
```

> If Chrome is already running, the debug port won't open. Make sure to fully quit Chrome before relaunching.

### 5. Start Claude Code

```bash
claude
```

The MCP Chrome DevTools server will connect automatically to Chrome via the WSL2 gateway IP.

## Usage with local dev server

This setup is especially useful during development. Run your dev server and let Claude Code see your app in real time:

```
Terminal 1: npm run dev              → your app on localhost:3000
Terminal 2: claude                   → Claude Code with browser access
Chrome:     open with debug flag     → Claude sees localhost:3000
```

Claude Code can then:
- Edit your code
- Take a screenshot to verify the result
- Click through your UI to test interactions
- Check console for errors
- All without leaving the terminal

## Available MCP Tools

| Tool | Description |
|---|---|
| `navigate_page` | Navigate to a URL, go back/forward, reload |
| `take_screenshot` | Capture the viewport or a specific element |
| `take_snapshot` | Get the accessibility tree (all elements with UIDs) |
| `click` | Click on an element by UID |
| `fill` | Type into input fields |
| `press_key` | Simulate keyboard shortcuts |
| `evaluate_script` | Run JavaScript in the page |
| `list_pages` / `select_page` | Manage browser tabs |
| `list_console_messages` | Read console output |
| `list_network_requests` | Inspect network activity |
| `resize_page` | Change viewport dimensions |
| `emulate` | Emulate dark mode, geolocation, network throttling |
| `performance_start_trace` | Record performance traces |

## Project Structure

```
mcp-chrome-wsl/
├── README.md
├── install.sh                  # One-command setup script
├── scripts/
│   ├── chrome-devtools-mcp-wrapper.sh  # WSL2 wrapper (resolves Windows IP)
│   └── launch-chrome.sh                # Launch Chrome with debug port
└── config/
    └── mcp-server.json                 # Example MCP server config for Claude Code
```

## Why a wrapper script?

On a native Linux or macOS setup, the MCP server connects to Chrome via `localhost:9222`. On WSL2, this doesn't work because:

1. Chrome runs on **Windows** (host)
2. The MCP server runs in **WSL2** (guest VM)
3. WSL2 uses a NAT network — `localhost` inside WSL ≠ `localhost` on Windows

The wrapper script solves this by dynamically getting the Windows host IP from `ip route show default` and passing it to the MCP server via `--browserUrl`.

## Troubleshooting

### MCP can't connect to Chrome
- Make sure Chrome was fully closed before relaunching with `--remote-debugging-port=9222`
- Verify the port is open from WSL2:
  ```bash
  WIN_HOST=$(ip route show default | awk '{print $3}')
  curl http://$WIN_HOST:9222/json/version
  ```

### Elements not found after page change
- DOM changes invalidate element UIDs — take a new snapshot after navigation or interactions that modify the page

### Chrome opens but debug port doesn't work
- Check no other Chrome instance is running (Task Manager → End all Chrome processes)
- Try a different port if 9222 is in use: `--remote-debugging-port=9333`

### Windows Firewall blocking the connection
- Allow inbound connections on port 9222 in Windows Firewall settings
- Or temporarily disable the firewall to test

## License

MIT
