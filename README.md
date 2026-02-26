# mcp-chrome-wsl

Setup pour utiliser **Chrome DevTools MCP** avec **Claude Code** sur **WSL2** — naviguer, capturer, cliquer et interagir avec votre navigateur en temps reel.

## Presentation

Ce projet connecte Claude Code (sous WSL2) a votre navigateur Chrome Windows via le serveur MCP Chrome DevTools. Une fois configure, Claude Code peut :

- Naviguer vers n'importe quelle URL (y compris les serveurs `localhost`)
- Capturer des screenshots et des snapshots d'accessibilite
- Cliquer sur des boutons, remplir des formulaires, interagir avec la page
- Lire les logs console et les requetes reseau
- Executer du JavaScript dans le navigateur
- Redimensionner le viewport pour tester le responsive
- **Lancer Chrome automatiquement** s'il n'est pas deja ouvert
- **Gerer plusieurs terminaux Claude Code en parallele** sans conflit

## Architecture

```
Terminal 1 (Claude Code)                    Terminal 2 (Claude Code)
        ↕ MCP stdio                                ↕ MCP stdio
Wrapper MCP (port auto: 9222)               Wrapper MCP (port auto: 9223)
        ↕ CDP Protocol                             ↕ CDP Protocol
Chrome instance 1 (Windows)                 Chrome instance 2 (Windows)
  profil: claude-debug-9222                   profil: claude-debug-9223
        ↓                                          ↓
        └──── localhost:3000 (meme serveur de dev) ─┘
```

Chaque terminal obtient **son propre Chrome isole** (port + profil uniques). Tous les Chrome pointent vers le meme serveur de dev — un seul `npm run dev` suffit.

## Prerequis

- Windows 11 avec WSL2 (Ubuntu)
- Google Chrome installe sur Windows
- Node.js >= 18 installe dans WSL2
- Claude Code installe dans WSL2
- `curl` disponible dans WSL2

## Installation rapide

```bash
git clone https://github.com/jeremywtp/mcp-chrome-wsl.git
cd mcp-chrome-wsl
chmod +x install.sh
./install.sh
```

L'installeur va :
1. Verifier les prerequis (node, npx, curl, claude, powershell.exe)
2. Copier le wrapper MCP vers `~/.local/bin/`
3. Copier le script PowerShell `chrome-debug.ps1` vers Windows (si absent)
4. Enregistrer le serveur MCP dans Claude Code (`claude mcp add`)
5. Lancer un diagnostic de verification

## Multi-session (isolation automatique)

Le probleme classique : deux terminaux Claude Code qui controlent le meme Chrome se battent pour la navigation (`/menu` vs `/privatisation` en boucle).

**La solution** : chaque instance du wrapper obtient automatiquement un Chrome isole :

| Terminal | Port CDP | Profil Chrome | Serveur de dev |
|----------|----------|---------------|----------------|
| Terminal 1 | 9222 | `UserData-claude-debug-9222` | localhost:3000 |
| Terminal 2 | 9223 | `UserData-claude-debug-9223` | localhost:3000 |
| Terminal 3 | 9224 | `UserData-claude-debug-9224` | localhost:3000 |

**Aucune configuration necessaire** — c'est le comportement par defaut.

### Comment ca marche

1. Au demarrage, le wrapper cherche un **port libre** dans la plage 9222-9232
2. **Verrouillage atomique** via `mkdir` dans `/tmp/mcp-chrome-locks/` (pas de race condition)
3. **Double verification** : lock fichier + scan des processus MCP actifs (evite les collisions meme si un lock est nettoye entre deux redemarrages)
4. Chrome est lance avec un **profil dedie au port** (`claude-debug-{port}`)
5. A la fermeture du terminal, le lock est libere et le port redevient disponible

### Forcer un port fixe

Pour retrouver l'ancien comportement (un seul Chrome partage) :

```bash
CDP_PORT=9222 claude
```

## Auto-launch Chrome

Le wrapper MCP lance Chrome automatiquement s'il n'est pas deja actif :

1. A chaque demarrage, le wrapper verifie si Chrome ecoute sur le port CDP alloue
2. Si Chrome n'est pas accessible, il le lance via le script PowerShell `chrome-debug.ps1`
3. Le script PowerShell :
   - Configure le portproxy WSL2 (`v4tov6`) pour que WSL puisse atteindre Chrome
   - Ajoute une regle firewall si necessaire
   - Ouvre Chrome avec un profil dedie pour ne pas interferer avec votre session normale
4. Le wrapper attend jusqu'a 12 secondes que Chrome soit pret avant de demarrer le serveur MCP

Resultat : il suffit de lancer `claude` — Chrome demarre tout seul si besoin.

## Variables d'environnement

| Variable | Defaut | Description |
|---|---|---|
| `CDP_PORT` | `auto` | Port CDP — `auto` = allocation dynamique, ou un numero pour forcer un port fixe |
| `CDP_PORT_MIN` | `9222` | Debut de la plage de ports (mode auto) |
| `CDP_PORT_MAX` | `9232` | Fin de la plage de ports (mode auto) |
| `CHROME_DEBUG_PS_SCRIPT` | `C:\Users\<USER>\scripts\chrome-debug.ps1` | Chemin Windows du script PowerShell de lancement |
| `WIN_USER` | *(detection auto)* | Nom d'utilisateur Windows (detecte via le filesystem, cache 24h) |

## Setup manuel

### 1. Copier le wrapper MCP

Le wrapper gere la detection reseau WSL2, l'auto-launch Chrome, l'allocation de port et le demarrage du serveur MCP :

```bash
mkdir -p ~/.local/bin
cp scripts/chrome-devtools-mcp-wrapper.sh ~/.local/bin/
chmod +x ~/.local/bin/chrome-devtools-mcp-wrapper.sh
```

### 2. Installer le script PowerShell

Copiez `config/chrome-debug.ps1` vers Windows :

```bash
WIN_USER=$(ls /mnt/c/Users/ | grep -vE '^(Public|Default|Default User|All Users)$' | head -1)
mkdir -p "/mnt/c/Users/${WIN_USER}/scripts"
cp config/chrome-debug.ps1 "/mnt/c/Users/${WIN_USER}/scripts/"
```

### 3. Enregistrer dans Claude Code

```bash
claude mcp add chrome-devtools -s user -- bash ~/.local/bin/chrome-devtools-mcp-wrapper.sh
```

Cela ajoute la configuration suivante dans `~/.claude.json` (voir [`config/mcp-server.json`](config/mcp-server.json) pour reference) :

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "type": "stdio",
      "command": "bash",
      "args": [
        "/home/<YOUR_USER>/.local/bin/chrome-devtools-mcp-wrapper.sh"
      ]
    }
  }
}
```

### 4. Lancer Chrome manuellement (optionnel)

Si vous preferez lancer Chrome manuellement plutot qu'avec l'auto-launch :

```bash
./scripts/launch-chrome.sh
```

Ou directement depuis Windows :

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Users\<USER>\scripts\chrome-debug.ps1
```

### 5. Demarrer Claude Code

```bash
claude
```

Le serveur MCP se connecte automatiquement a Chrome. Si Chrome n'est pas actif, il sera lance automatiquement.

## Utilisation avec un serveur de dev local

Ce setup est particulierement utile pendant le developpement :

```
Terminal 1 : npm run dev              → votre app sur localhost:3000
Terminal 2 : claude                   → Claude Code + Chrome sur port CDP 9222
Terminal 3 : claude                   → Claude Code + Chrome sur port CDP 9223
Chrome 1 & 2 :                        → les deux voient localhost:3000
```

Chaque terminal Claude peut :
- Modifier votre code
- Capturer un screenshot pour verifier le resultat
- Naviguer dans votre interface pour tester les interactions
- Verifier la console pour les erreurs
- Tout ca sans conflit avec l'autre terminal

## Diagnostic

Un script de diagnostic est inclus pour verifier que tout fonctionne :

```bash
./scripts/check-chrome.sh
```

Il verifie :
- Le mode reseau WSL2 (NAT ou mirrored)
- La connectivite CDP vers Chrome
- Les onglets Chrome ouverts
- La presence de PowerShell et du script de lancement
- Node.js et npx

Exemple de sortie :

```
==============================
 MCP Chrome DevTools — Diagnostic
==============================

[RESEAU] Detection du mode reseau WSL2
  [OK] Mode mirrored detecte (localhost direct)

[CDP] Test de connexion CDP sur localhost:9222
  [OK] Chrome CDP accessible — Chrome/145.x.x.x
  [INFO] WebSocket: ws://localhost:9222/devtools/browser/...

[TABS] Liste des onglets Chrome
  [OK] 3 onglet(s) detecte(s)

[PS] Verification PowerShell et script de lancement
  [OK] powershell.exe accessible depuis WSL
  [OK] chrome-debug.ps1 trouve

[NPX] Verification de Node.js et npx
  [OK] Node.js installe : v24.x.x
  [OK] npx disponible

==============================
 Resume : 8 OK  0 FAIL  0 WARN
==============================
```

## Outils MCP disponibles

| Outil | Description |
|---|---|
| `navigate_page` | Naviguer vers une URL, retour/avant, recharger |
| `take_screenshot` | Capturer le viewport ou un element specifique |
| `take_snapshot` | Obtenir l'arbre d'accessibilite (elements avec UIDs) |
| `click` | Cliquer sur un element par UID |
| `fill` | Saisir du texte dans un champ |
| `press_key` | Simuler des raccourcis clavier |
| `evaluate_script` | Executer du JavaScript dans la page |
| `list_pages` / `select_page` | Gerer les onglets du navigateur |
| `list_console_messages` | Lire les messages console |
| `list_network_requests` | Inspecter les requetes reseau |
| `resize_page` | Modifier les dimensions du viewport |
| `emulate` | Emuler mode sombre, geolocalisation, throttling reseau |
| `performance_start_trace` | Enregistrer des traces de performance |

## Structure du projet

```
mcp-chrome-wsl/
├── README.md
├── install.sh                          # Script d'installation
├── scripts/
│   ├── chrome-devtools-mcp-wrapper.sh  # Wrapper MCP (multi-session + auto-launch + reseau WSL2)
│   ├── launch-chrome.sh                # Lancement Chrome standalone
│   └── check-chrome.sh                 # Diagnostic de verification
└── config/
    ├── mcp-server.json                 # Exemple de config MCP pour Claude Code
    └── chrome-debug.ps1                # Script PowerShell (reference)
```

## Pourquoi un wrapper ?

Sur un setup Linux ou macOS natif, le serveur MCP se connecte a Chrome via `localhost:9222`. Sur WSL2, ca ne fonctionne pas directement car :

1. Chrome tourne sur **Windows** (hote)
2. Le serveur MCP tourne dans **WSL2** (VM invitee)
3. WSL2 utilise un reseau NAT — `localhost` dans WSL ≠ `localhost` sur Windows

Le wrapper resout ce probleme en :
- Detectant automatiquement le mode reseau (NAT ou mirrored)
- Resolvant l'IP de l'hote Windows dynamiquement
- Lancant Chrome automatiquement si besoin via PowerShell
- **Isolant chaque terminal** avec son propre Chrome (port + profil dedies)

## Troubleshooting

### Le MCP ne se connecte pas a Chrome

1. Lancez le diagnostic :
   ```bash
   ./scripts/check-chrome.sh
   ```
2. Verifiez que Chrome est bien lance avec le port de debug :
   ```bash
   curl http://localhost:9222/json/version
   ```
3. Si Chrome est deja ouvert sans debug, fermez-le completement (Gestionnaire des taches → terminer tous les processus Chrome) puis relancez via `./scripts/launch-chrome.sh`.

### Chrome se lance mais le port n'est pas accessible depuis WSL

Le portproxy WSL2 n'est peut-etre pas configure. Le script `chrome-debug.ps1` le fait automatiquement, mais il faut des droits administrateur. Relancez :

```powershell
# En tant qu'administrateur dans PowerShell
netsh interface portproxy add v4tov6 listenaddress=0.0.0.0 listenport=9222 connectaddress=::1 connectport=9222
```

### Les elements ne sont pas trouves apres un changement de page

Les modifications du DOM invalident les UIDs des elements. Prenez un nouveau snapshot apres chaque navigation ou interaction qui modifie la page.

### Le firewall Windows bloque la connexion

- Autorisez les connexions entrantes sur le port 9222 dans les parametres du pare-feu Windows
- Ou utilisez le script `chrome-debug.ps1` qui configure la regle automatiquement

### Deux terminaux se battent pour la meme page

Ce probleme est resolu automatiquement par le mode multi-session. Si ca arrive encore :

1. Verifiez les locks actifs :
   ```bash
   ls -la /tmp/mcp-chrome-locks/
   ```
2. Verifiez les processus MCP :
   ```bash
   ps aux | grep chrome-devtools-mcp | grep browserUrl
   ```
3. Nettoyez et relancez :
   ```bash
   rm -rf /tmp/mcp-chrome-locks
   # Puis relancez vos terminaux Claude Code
   ```

### Le MCP timeout au demarrage (failed)

Le wrapper a 30 secondes pour demarrer. Si le timeout est atteint :

1. Relancez le MCP depuis Claude Code : `/mcp` → selectionner `chrome-devtools` → restart
2. Le cache du username Windows accelere les demarrages suivants (fichier `/tmp/.mcp-chrome-win-user`)

### Mode mirrored : localhost ne fonctionne pas

Si vous utilisez le mode `networkingMode=mirrored` dans `.wslconfig` et que la connexion ne fonctionne pas, verifiez :

```bash
# Le wrapper detecte automatiquement le mode — forcez le diagnostic :
./scripts/check-chrome.sh
```

## Licence

MIT
