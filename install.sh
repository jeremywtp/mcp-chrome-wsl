#!/bin/bash
# Install script for Chrome DevTools MCP on WSL2
set -e

WRAPPER_PATH="$HOME/.local/bin/chrome-devtools-mcp-wrapper.sh"

echo "=== Chrome DevTools MCP — WSL2 Setup ==="
echo ""

# 1. Install npm package
echo "[1/3] Installing chrome-devtools-mcp..."
npm install -g chrome-devtools-mcp@latest

# 2. Create wrapper script
echo "[2/3] Creating wrapper script at $WRAPPER_PATH..."
mkdir -p "$(dirname "$WRAPPER_PATH")"
cat > "$WRAPPER_PATH" << 'WRAPPER'
#!/bin/bash
# Wrapper for chrome-devtools-mcp from WSL2
# Dynamically resolves the Windows host IP (WSL2 NAT gateway)
WIN_HOST=$(ip route show default | awk '{print $3}')
exec npx chrome-devtools-mcp@latest --browserUrl "http://${WIN_HOST}:9222" "$@"
WRAPPER
chmod +x "$WRAPPER_PATH"

# 3. Add MCP server to Claude Code
echo "[3/3] Adding MCP server to Claude Code..."
claude mcp add chrome-devtools -s user -- bash "$WRAPPER_PATH"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Close all Chrome windows"
echo "  2. Relaunch Chrome with: /mnt/c/Program\ Files/Google/Chrome/Application/chrome.exe --remote-debugging-port=9222"
echo "  3. Start Claude Code: claude"
echo ""
echo "The MCP server will auto-connect to Chrome on port 9222."
