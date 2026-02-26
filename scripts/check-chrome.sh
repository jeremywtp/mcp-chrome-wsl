#!/bin/bash
# Script de diagnostic standalone pour le setup MCP Chrome DevTools sur WSL2
# Verifie la connectivite CDP, le reseau WSL2, les outils necessaires
# Usage : ./scripts/check-chrome.sh

set -euo pipefail

CDP_PORT="${CDP_PORT:-9222}"
PASS=0
FAIL=0
WARN=0

# Couleurs
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

ok()   { echo -e "  ${GREEN}[OK]${RESET} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[FAIL]${RESET} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[WARN]${RESET} $1"; WARN=$((WARN + 1)); }
info() { echo -e "  ${CYAN}[INFO]${RESET} $1"; }

# ── Detection du username Windows ──
WIN_USER="$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')"

echo ""
echo "=============================="
echo " MCP Chrome DevTools — Diagnostic"
echo "=============================="
echo ""

# ── [RESEAU] Mode reseau WSL2 ──
echo -e "${CYAN}[RESEAU]${RESET} Detection du mode reseau WSL2"

WSLCONFIG="/mnt/c/Users/${WIN_USER}/.wslconfig"
if [[ -f "$WSLCONFIG" ]] && grep -qi 'networkingMode=mirrored' "$WSLCONFIG" 2>/dev/null; then
  NETWORK_MODE="mirrored"
  WIN_HOST="localhost"
  ok "Mode mirrored detecte (localhost direct)"
else
  NETWORK_MODE="NAT"
  WIN_HOST=$(ip route show default | awk '{print $3}')
  ok "Mode NAT detecte (host gateway: ${WIN_HOST})"
fi
echo ""

# ── [CDP] Connexion au Chrome DevTools Protocol ──
echo -e "${CYAN}[CDP]${RESET} Test de connexion CDP sur ${WIN_HOST}:${CDP_PORT}"

if curl -s --connect-timeout 3 "http://${WIN_HOST}:${CDP_PORT}/json/version" > /dev/null 2>&1; then
  CDP_VERSION=$(curl -s --connect-timeout 3 "http://${WIN_HOST}:${CDP_PORT}/json/version")
  BROWSER=$(echo "$CDP_VERSION" | grep -oP '"Browser"\s*:\s*"\K[^"]+' || echo "inconnu")
  WS_URL=$(echo "$CDP_VERSION" | grep -oP '"webSocketDebuggerUrl"\s*:\s*"\K[^"]+' || echo "inconnu")
  ok "Chrome CDP accessible — ${BROWSER}"
  info "WebSocket: ${WS_URL}"
else
  fail "Chrome CDP non accessible sur http://${WIN_HOST}:${CDP_PORT}"
  info "Lancer Chrome avec : powershell.exe -ExecutionPolicy Bypass -File 'C:\\Users\\${WIN_USER}\\scripts\\chrome-debug.ps1'"
fi
echo ""

# ── [TABS] Onglets ouverts ──
echo -e "${CYAN}[TABS]${RESET} Liste des onglets Chrome"

TABS_JSON=$(curl -s --connect-timeout 3 "http://${WIN_HOST}:${CDP_PORT}/json/list" 2>/dev/null || echo "")
if [[ -n "$TABS_JSON" && "$TABS_JSON" != "[]" ]]; then
  TAB_COUNT=$(echo "$TABS_JSON" | grep -c '"id"' || echo "0")
  ok "${TAB_COUNT} onglet(s) detecte(s)"
  # Afficher les 5 premiers onglets
  echo "$TABS_JSON" | grep -oP '"title"\s*:\s*"\K[^"]+' | head -5 | while read -r title; do
    info "  - ${title}"
  done
else
  warn "Aucun onglet trouve (Chrome non lance ou pas de page ouverte)"
fi
echo ""

# ── [PS] PowerShell et script chrome-debug.ps1 ──
echo -e "${CYAN}[PS]${RESET} Verification PowerShell et script de lancement"

if command -v powershell.exe &> /dev/null; then
  ok "powershell.exe accessible depuis WSL"
else
  fail "powershell.exe non trouve dans le PATH"
fi

PS_SCRIPT="/mnt/c/Users/${WIN_USER}/scripts/chrome-debug.ps1"
if [[ -f "$PS_SCRIPT" ]]; then
  ok "chrome-debug.ps1 trouve : ${PS_SCRIPT}"
else
  warn "chrome-debug.ps1 non trouve : ${PS_SCRIPT}"
  info "Une copie de reference est disponible dans config/chrome-debug.ps1"
fi
echo ""

# ── [NPX] Node.js et npx ──
echo -e "${CYAN}[NPX]${RESET} Verification de Node.js et npx"

if command -v node &> /dev/null; then
  NODE_VERSION=$(node --version)
  ok "Node.js installe : ${NODE_VERSION}"
else
  fail "Node.js non installe"
fi

if command -v npx &> /dev/null; then
  NPX_VERSION=$(npx --version 2>/dev/null || echo "inconnu")
  ok "npx disponible : v${NPX_VERSION}"
else
  fail "npx non disponible (installer Node.js >= 18)"
fi
echo ""

# ── Resume ──
echo "=============================="
echo -e " Resume : ${GREEN}${PASS} OK${RESET}  ${RED}${FAIL} FAIL${RESET}  ${YELLOW}${WARN} WARN${RESET}"
echo "=============================="
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
