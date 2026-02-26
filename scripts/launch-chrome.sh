#!/bin/bash
set -euo pipefail

# =============================================================================
# Lance Chrome en mode debug CDP depuis WSL2 via le script PowerShell
# Verifie ensuite que Chrome est accessible depuis WSL.
# Usage : ./launch-chrome.sh [port]
# =============================================================================

# ── Configuration ──
CDP_PORT="${1:-${CDP_PORT:-9222}}"
WIN_USER="${WIN_USER:-$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')}"
CHROME_DEBUG_PS_SCRIPT="${CHROME_DEBUG_PS_SCRIPT:-C:\\Users\\${WIN_USER}\\scripts\\chrome-debug.ps1}"

# ── Fonctions de log ──
log_info()  { echo "[INFO]  $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# ── Detection du mode reseau WSL2 ──
detect_win_host() {
  local wslconfig="/mnt/c/Users/${WIN_USER}/.wslconfig"
  if [[ -f "$wslconfig" ]] && grep -qi 'networkingMode=mirrored' "$wslconfig" 2>/dev/null; then
    log_info "Mode reseau WSL2 : mirrored"
    echo "localhost"
  else
    local gateway
    gateway=$(ip route show default | awk '{print $3}')
    log_info "Mode reseau WSL2 : NAT (gateway=$gateway)"
    echo "$gateway"
  fi
}

# ── Main ──
main() {
  local win_host
  win_host=$(detect_win_host)

  # Verifier si Chrome ecoute deja
  if curl -s --connect-timeout 2 "http://${win_host}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    log_info "Chrome deja actif sur http://${win_host}:${CDP_PORT}"
    curl -s "http://${win_host}:${CDP_PORT}/json/version" | head -5
    exit 0
  fi

  # Lancer Chrome via le script PowerShell
  log_info "Lancement de Chrome via PowerShell (port ${CDP_PORT})..."
  powershell.exe -ExecutionPolicy Bypass -File "$CHROME_DEBUG_PS_SCRIPT" -Port "$CDP_PORT" || {
    log_error "Echec du lancement de Chrome via PowerShell"
    exit 1
  }

  # Attendre que Chrome soit accessible depuis WSL (max 12s)
  log_info "Verification depuis WSL..."
  local max_attempts=12
  local attempt=0

  while (( attempt < max_attempts )); do
    if curl -s --connect-timeout 2 "http://${win_host}:${CDP_PORT}/json/version" >/dev/null 2>&1; then
      log_info "Chrome CDP disponible sur http://${win_host}:${CDP_PORT}"
      curl -s "http://${win_host}:${CDP_PORT}/json/version"
      exit 0
    fi
    attempt=$((attempt + 1))
    log_info "Attente Chrome CDP... (${attempt}/${max_attempts})"
    sleep 1
  done

  log_error "Chrome CDP non disponible apres ${max_attempts}s"
  exit 1
}

main
