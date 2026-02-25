#!/bin/bash
# Wrapper for chrome-devtools-mcp from WSL2
# Detects network mode and resolves Windows host IP

# In mirrored mode, localhost works directly
if grep -qi 'networkingMode=mirrored' /mnt/c/Users/neozi/.wslconfig 2>/dev/null; then
  WIN_HOST="localhost"
else
  # Classic NAT mode: WSL2 gateway points to Windows
  WIN_HOST=$(ip route show default | awk '{print $3}')
fi

exec npx chrome-devtools-mcp@latest --browserUrl "http://${WIN_HOST}:9222" "$@"
