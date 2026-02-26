#!/bin/bash
set -euo pipefail

# =============================================================================
# Wrapper MCP Chrome DevTools pour WSL2
# Auto-detecte le mode reseau, verifie si Chrome tourne, le lance si besoin,
# puis demarre le serveur MCP via npx.
#
# MULTI-SESSION : chaque instance obtient automatiquement son propre Chrome
# sur un port libre (9222-9232) avec un profil dedie, pour eviter les
# conflits entre terminaux Claude Code concurrents.
#
# IMPORTANT : tout le diagnostic va vers stderr — stdout est reserve au
#             protocole stdio MCP.
# =============================================================================

# ── Configuration (surchargeable via variables d'environnement) ──
# CDP_PORT : "auto" (defaut) = allocation automatique d'un port libre
#            "9222" (ou autre numero) = port fixe (ancien comportement)
CDP_PORT="${CDP_PORT:-auto}"
CDP_PORT_MIN="${CDP_PORT_MIN:-9222}"
CDP_PORT_MAX="${CDP_PORT_MAX:-9232}"
WIN_USER="${WIN_USER:-$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')}"
CHROME_DEBUG_PS_SCRIPT="${CHROME_DEBUG_PS_SCRIPT:-C:\\Users\\${WIN_USER}\\scripts\\chrome-debug.ps1}"

# Repertoire des locks pour la coordination multi-session
LOCK_DIR="/tmp/mcp-chrome-locks"

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
  local host="$1" port="$2"
  curl -s --connect-timeout 2 "http://${host}:${port}/json/version" >/dev/null 2>&1
}

# ── Verrouillage atomique d'un port (via mkdir) ──
try_lock_port() {
  local port="$1"
  local lockdir="${LOCK_DIR}/port-${port}"

  # Tenter un lock atomique (mkdir est atomique sur le filesystem)
  if mkdir "$lockdir" 2>/dev/null; then
    # Ecrire le PID immediatement apres mkdir pour minimiser la fenetre de race
    echo "$$" > "${lockdir}/pid"
    return 0
  fi

  # Lock existant : verifier si le processus proprietaire est encore vivant
  local lock_pid
  lock_pid=$(cat "${lockdir}/pid" 2>/dev/null || echo "")

  # Si pas de PID (race condition: mkdir ok mais pid pas encore ecrit), attendre un instant
  if [[ -z "$lock_pid" ]]; then
    sleep 0.1
    lock_pid=$(cat "${lockdir}/pid" 2>/dev/null || echo "")
  fi

  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    return 1  # Port reserve par un wrapper actif
  fi

  # Lock orphelin : nettoyer et retenter
  rm -rf "$lockdir"
  if mkdir "$lockdir" 2>/dev/null; then
    echo "$$" > "${lockdir}/pid"
    return 0
  fi

  return 1  # Un autre wrapper a ete plus rapide
}

# ── Trouver et reserver un port libre pour Chrome CDP ──
# Strategie : on prend le premier port qu'on peut verrouiller.
# Si Chrome est deja actif dessus (orphelin d'une session precedente),
# on le reutilise au lieu d'en lancer un nouveau.
find_free_port() {
  local host="$1"
  mkdir -p "$LOCK_DIR"

  for port in $(seq "$CDP_PORT_MIN" "$CDP_PORT_MAX"); do
    # Verifier si un autre wrapper a deja reserve ce port
    if ! try_lock_port "$port"; then
      log_info "Port ${port} : reserve par un autre wrapper"
      continue
    fi

    # Port verrouille par nous ! Chrome peut ou non deja tourner dessus.
    # Dans les deux cas, main() gerera (reutilisation ou lancement).
    echo "$port"
    return 0
  done

  return 1
}

# ── Lancement de Chrome via le script PowerShell ──
launch_chrome() {
  local port="$1"
  local profile_name="claude-debug-${port}"

  log_info "Chrome non detecte sur le port ${port}, lancement via PowerShell..."
  log_info "Profil dedie : ${profile_name}"
  powershell.exe -ExecutionPolicy Bypass -File "$CHROME_DEBUG_PS_SCRIPT" \
    -Port "$port" -ProfileName "$profile_name" >&2 2>&1 || {
    log_error "Echec du lancement de Chrome via PowerShell"
    return 1
  }
}

# ── Boucle d'attente Chrome CDP (max 12s, interval 1s) ──
wait_for_chrome() {
  local host="$1" port="$2"
  local max_attempts=12
  local attempt=0

  while (( attempt < max_attempts )); do
    if check_chrome_cdp "$host" "$port"; then
      log_info "Chrome CDP disponible sur http://${host}:${port}"
      return 0
    fi
    attempt=$((attempt + 1))
    log_info "Attente Chrome CDP... (${attempt}/${max_attempts})"
    sleep 1
  done

  log_error "Chrome CDP non disponible apres ${max_attempts}s sur http://${host}:${port}"
  return 1
}

# ── Nettoyage a la sortie ──
cleanup() {
  log_info "Nettoyage du wrapper MCP (port ${CDP_PORT})"
  rm -rf "${LOCK_DIR}/port-${CDP_PORT}" 2>/dev/null || true
}

# ── Main ──
main() {
  log_info "Demarrage du wrapper MCP Chrome DevTools"
  log_info "Utilisateur Windows : ${WIN_USER}"

  # Detecter l'adresse de l'hote Windows
  local win_host
  win_host=$(detect_win_host)

  # Determiner le port CDP a utiliser
  if [[ "$CDP_PORT" == "auto" ]]; then
    log_info "Mode multi-session : recherche d'un port libre (${CDP_PORT_MIN}-${CDP_PORT_MAX})..."
    CDP_PORT=$(find_free_port "$win_host") || {
      log_error "Aucun port libre dans la plage ${CDP_PORT_MIN}-${CDP_PORT_MAX}"
      log_error "Fermez des sessions ou augmentez CDP_PORT_MAX"
      exit 1
    }
    log_info "Port libre alloue : ${CDP_PORT}"
  else
    log_info "Port CDP (fixe) : ${CDP_PORT}"
    # Creer un lock meme en mode fixe pour la visibilite
    mkdir -p "$LOCK_DIR"
    try_lock_port "$CDP_PORT" || log_warn "Port ${CDP_PORT} deja reserve par un autre wrapper"
  fi

  # Installer le trap de nettoyage (libere le lock a la sortie)
  trap cleanup EXIT

  # Verifier si Chrome est deja disponible sur ce port
  if check_chrome_cdp "$win_host" "$CDP_PORT"; then
    log_info "Chrome deja actif sur http://${win_host}:${CDP_PORT}"
  else
    # Lancer Chrome puis attendre qu'il soit pret
    launch_chrome "$CDP_PORT"
    if ! wait_for_chrome "$win_host" "$CDP_PORT"; then
      log_error "Impossible de se connecter a Chrome. Abandon."
      exit 1
    fi
  fi

  # Demarrer le serveur MCP
  # On ne fait PAS exec pour que le trap EXIT puisse nettoyer le lock.
  # npx herite stdin/stdout du shell — le protocole stdio MCP fonctionne normalement.
  log_info "Lancement du serveur MCP sur le port ${CDP_PORT}..."
  npx chrome-devtools-mcp@latest --browserUrl "http://${win_host}:${CDP_PORT}" "$@"
}

main "$@"
