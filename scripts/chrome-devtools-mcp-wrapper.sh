#!/bin/bash
# Wrapper for chrome-devtools-mcp from WSL2
# Dynamically resolves the Windows host IP (WSL2 NAT gateway)
WIN_HOST=$(ip route show default | awk '{print $3}')
exec npx chrome-devtools-mcp@latest --browserUrl "http://${WIN_HOST}:9222" "$@"
