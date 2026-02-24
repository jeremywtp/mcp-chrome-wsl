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
        ↕ CDP Protocol
MCP Chrome DevTools Server (WSL2)
        ↕ MCP Protocol
Claude Code (WSL2)
```

## Prerequisites

- Windows 11 with WSL2 (Ubuntu)
- Google Chrome installed on Windows
- Node.js installed in WSL2
- Claude Code installed in WSL2

## Setup

### 1. Install the MCP package

```bash
npm install -g @anthropic-ai/mcp-chrome-devtools
```

### 2. Configure Claude Code

Add the MCP server to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-chrome-devtools"]
    }
  }
}
```

Or use the `/mcp` command inside Claude Code to add it interactively.

### 3. Launch Chrome with remote debugging

**Important:** Close all Chrome instances first, then relaunch with the debugging flag.

```bash
"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" --remote-debugging-port=9222
```

> If Chrome is already running, the debug port won't open. Make sure to fully quit Chrome before relaunching.

### 4. Start Claude Code

```bash
claude
```

The MCP Chrome DevTools server will connect automatically to Chrome on port 9222.

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

## Troubleshooting

### MCP can't connect to Chrome
- Make sure Chrome was fully closed before relaunching with `--remote-debugging-port=9222`
- Verify the port is open: `curl http://localhost:9222/json/version`

### Elements not found after page change
- The DOM changes invalidate element UIDs — take a new snapshot after navigation or interactions that modify the page

### Chrome opens but debug port doesn't work
- Check no other Chrome instance is running in the background (Task Manager → End all Chrome processes)
- Try a different port if 9222 is in use: `--remote-debugging-port=9333`

## License

MIT
