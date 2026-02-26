#!/bin/bash
set -e

# =============================================================================
# Installeur MCP Chrome DevTools pour WSL2
# Configure le wrapper, enregistre le serveur MCP dans Claude Code,
# et lance un diagnostic de verification.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER_SRC="${SCRIPT_DIR}/scripts/chrome-devtools-mcp-wrapper.sh"
WRAPPER_DEST="$HOME/.local/bin/chrome-devtools-mcp-wrapper.sh"
PS_SCRIPT_SRC="${SCRIPT_DIR}/config/chrome-debug.ps1"

# ── Couleurs ──
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

ok()   { echo -e "  ${GREEN}[OK]${RESET} $1"; }
fail() { echo -e "  ${RED}[FAIL]${RESET} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
info() { echo -e "  ${CYAN}[INFO]${RESET} $1"; }

echo ""
echo "======================================"
echo " MCP Chrome DevTools — Installation"
echo "======================================"
echo ""

# ── [1/4] Verification des prerequis ──
echo -e "${CYAN}[1/4]${RESET} Verification des prerequis..."
HAS_ERROR=0

# Prerequis obligatoires (erreur fatale si absent)
for cmd in node npx curl claude; do
  if command -v "$cmd" &> /dev/null; then
    ok "$cmd trouve : $(command -v "$cmd")"
  else
    fail "$cmd non trouve — requis pour le fonctionnement"
    HAS_ERROR=1
  fi
done

# Prerequis optionnels (warning si absent)
if command -v powershell.exe &> /dev/null; then
  ok "powershell.exe accessible depuis WSL"
else
  warn "powershell.exe non trouve — l'auto-launch Chrome ne fonctionnera pas"
fi

# Verifier chrome-debug.ps1 cote Windows
WIN_USER="${WIN_USER:-$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "")}"
PS_DEST="/mnt/c/Users/${WIN_USER}/scripts/chrome-debug.ps1"

if [[ -f "$PS_DEST" ]]; then
  ok "chrome-debug.ps1 deja installe : ${PS_DEST}"
elif [[ -n "$WIN_USER" && -f "$PS_SCRIPT_SRC" ]]; then
  info "Installation de chrome-debug.ps1 vers ${PS_DEST}..."
  mkdir -p "$(dirname "$PS_DEST")"
  cp "$PS_SCRIPT_SRC" "$PS_DEST"
  ok "chrome-debug.ps1 copie vers ${PS_DEST}"
else
  warn "chrome-debug.ps1 non installe — l'auto-launch Chrome ne fonctionnera pas"
  info "Copiez manuellement : config/chrome-debug.ps1 → C:\\Users\\<USER>\\scripts\\chrome-debug.ps1"
fi

if [[ $HAS_ERROR -eq 1 ]]; then
  echo ""
  fail "Prerequis manquants. Corrigez les erreurs ci-dessus avant de continuer."
  exit 1
fi
echo ""

# ── [2/4] Copie du wrapper MCP ──
echo -e "${CYAN}[2/4]${RESET} Installation du wrapper MCP..."

if [[ ! -f "$WRAPPER_SRC" ]]; then
  fail "Wrapper source introuvable : ${WRAPPER_SRC}"
  exit 1
fi

mkdir -p "$(dirname "$WRAPPER_DEST")"
cp "$WRAPPER_SRC" "$WRAPPER_DEST"
chmod +x "$WRAPPER_DEST"
ok "Wrapper copie vers ${WRAPPER_DEST}"
echo ""

# ── [3/4] Enregistrement du serveur MCP dans Claude Code ──
echo -e "${CYAN}[3/4]${RESET} Enregistrement du serveur MCP dans Claude Code..."
claude mcp add chrome-devtools -s user -- bash "$WRAPPER_DEST"
ok "Serveur MCP enregistre (scope: user)"
echo ""

# ── [4/4] Diagnostic ──
echo -e "${CYAN}[4/4]${RESET} Lancement du diagnostic..."
echo ""

CHECK_SCRIPT="${SCRIPT_DIR}/scripts/check-chrome.sh"
if [[ -x "$CHECK_SCRIPT" ]]; then
  bash "$CHECK_SCRIPT" || true
else
  warn "Script de diagnostic non trouve : ${CHECK_SCRIPT}"
fi

echo ""
echo "======================================"
echo -e " ${GREEN}Installation terminee !${RESET}"
echo "======================================"
echo ""
echo "Prochaines etapes :"
echo "  1. Lancez Chrome en mode debug :"
echo "     ./scripts/launch-chrome.sh"
echo "  2. Demarrez Claude Code :"
echo "     claude"
echo ""
echo "Variables d'environnement disponibles :"
echo "  CDP_PORT=9222                  Port CDP (defaut: 9222)"
echo "  CHROME_DEBUG_PS_SCRIPT=...     Chemin du script PowerShell"
echo ""
