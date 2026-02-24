#!/bin/bash
# Launch Chrome from WSL2 with remote debugging enabled
# Make sure all Chrome instances are closed before running this

CHROME_PATH="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
PORT=9222

echo "Launching Chrome with remote debugging on port $PORT..."
"$CHROME_PATH" --remote-debugging-port=$PORT &

echo "Chrome launched. Verify with:"
echo "  curl http://localhost:$PORT/json/version"
