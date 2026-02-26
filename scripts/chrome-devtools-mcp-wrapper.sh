#!/bin/bash
set -euo pipefail

# =============================================================================
# Wrapper MCP Chrome DevTools pour WSL2
# Auto-detecte le mode reseau, verifie si Chrome tourne, le lance si besoin,
# puis demarre le serveur MCP via npx.
# IMPORTANT : tout le diagnostic va vers stderr — stdout est reserve au
#             protocole stdio MCP.
# =============================================================================

# ── Configuration (surchargeable via variables d'environnement) ──
CDP_PORT="${CDP_PORT:-9222}"
WIN_USER="${WIN_USER:-$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')}"
CHROME_DEBUG_PS_SCRIPT="${CHROME_DEBUG_PS_SCRIPT:-C:\\Users\\${WIN_USER}\\scripts\\chrome-debug.ps1}"

# ── Fonctions de log (tout vers stderr) ──
log_info()  { echo "[INFO]  $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# ── Detection du mode reseau WSL2 (mirrored vs NAT) ──
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

# ── Health check Chrome CDP ──
check_chrome_cdp() {
  local host="$1"
  curl -s --connect-timeout 2 "http://${host}:${CDP_PORT}/json/version" >/dev/null 2>&1
}

# ── Lancement de Chrome via le script PowerShell ──
launch_chrome() {
  log_info "Chrome non detecte sur le port ${CDP_PORT}, lancement via PowerShell..."
  powershell.exe -ExecutionPolicy Bypass -File "$CHROME_DEBUG_PS_SCRIPT" -Port "$CDP_PORT" >&2 2>&1 || {
    log_error "Echec du lancement de Chrome via PowerShell"
    return 1
  }
}

# ── Boucle d'attente Chrome CDP (max 12s, interval 1s) ──
wait_for_chrome() {
  local host="$1"
  local max_attempts=12
  local attempt=0

  while (( attempt < max_attempts )); do
    if check_chrome_cdp "$host"; then
      log_info "Chrome CDP disponible sur http://${host}:${CDP_PORT}"
      return 0
    fi
    attempt=$((attempt + 1))
    log_info "Attente Chrome CDP... (${attempt}/${max_attempts})"
    sleep 1
  done

  log_error "Chrome CDP non disponible apres ${max_attempts}s sur http://${host}:${CDP_PORT}"
  return 1
}

# ── Main ──
main() {
  log_info "Demarrage du wrapper MCP Chrome DevTools"
  log_info "Utilisateur Windows : ${WIN_USER}"
  log_info "Port CDP : ${CDP_PORT}"

  # Detecter l'adresse de l'hote Windows
  local win_host
  win_host=$(detect_win_host)

  # Verifier si Chrome est deja disponible
  if check_chrome_cdp "$win_host"; then
    log_info "Chrome deja actif sur http://${win_host}:${CDP_PORT}"
  else
    # Lancer Chrome puis attendre qu'il soit pret
    launch_chrome
    if ! wait_for_chrome "$win_host"; then
      log_error "Impossible de se connecter a Chrome. Abandon."
      exit 1
    fi
  fi

  # Demarrer le serveur MCP (exec remplace le processus — stdout libre pour stdio)
  log_info "Lancement du serveur MCP..."
  exec npx chrome-devtools-mcp@latest --browserUrl "http://${win_host}:${CDP_PORT}" "$@"
}

main "$@"
