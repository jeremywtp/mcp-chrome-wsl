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

## Architecture

```
Chrome (Windows) --remote-debugging-port=9222
        ↕ CDP Protocol (via WSL2 NAT gateway ou localhost en mode mirrored)
Wrapper MCP (WSL2) — auto-launch Chrome si besoin
        ↕ MCP Protocol (stdio)
Claude Code (WSL2)
```

Le wrapper detecte automatiquement le mode reseau WSL2 (NAT ou mirrored) et resout l'adresse de l'hote Windows en consequence.

## Prerequis

- Windows 11 avec WSL2 (Ubuntu)
- Google Chrome installe sur Windows
- Node.js >= 18 installe dans WSL2
- Claude Code installe dans WSL2
- `curl` disponible dans WSL2

## Installation rapide

```bash
git clone https://github.com/user/mcp-chrome-wsl.git
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

## Auto-launch Chrome

Le wrapper MCP lance Chrome automatiquement s'il n'est pas deja actif :

1. A chaque demarrage du serveur MCP, le wrapper verifie si Chrome ecoute sur le port CDP
2. Si Chrome n'est pas accessible, il le lance via le script PowerShell `chrome-debug.ps1`
3. Le script PowerShell :
   - Configure le portproxy WSL2 (`v4tov6`) pour que WSL puisse atteindre Chrome
   - Ajoute une regle firewall si necessaire
   - Ouvre Chrome avec un profil dedie (`claude-debug`) pour ne pas interferer avec votre session normale
4. Le wrapper attend jusqu'a 12 secondes que Chrome soit pret avant de demarrer le serveur MCP

Resultat : il suffit de lancer `claude` — Chrome demarre tout seul si besoin.

## Multi-session CDP

Le protocole CDP (Chrome DevTools Protocol) supporte nativement les clients multiples. Cela signifie :

- Vous pouvez avoir **plusieurs instances Claude Code** connectees au meme Chrome simultanement
- Les DevTools de Chrome peuvent rester ouverts en parallele
- Chaque client MCP recoit les evenements CDP independamment

Aucune configuration supplementaire n'est necessaire.

## Variables d'environnement

| Variable | Defaut | Description |
|---|---|---|
| `CDP_PORT` | `9222` | Port du Chrome DevTools Protocol |
| `CHROME_DEBUG_PS_SCRIPT` | `C:\Users\<USER>\scripts\chrome-debug.ps1` | Chemin Windows du script PowerShell de lancement |
| `WIN_USER` | *(detection auto)* | Nom d'utilisateur Windows (detecte via `cmd.exe`) |

Exemple d'utilisation avec un port personnalise :

```bash
CDP_PORT=9333 claude
```

## Setup manuel

### 1. Copier le wrapper MCP

Le wrapper gere la detection reseau WSL2, l'auto-launch Chrome et le demarrage du serveur MCP :

```bash
mkdir -p ~/.local/bin
cp scripts/chrome-devtools-mcp-wrapper.sh ~/.local/bin/
chmod +x ~/.local/bin/chrome-devtools-mcp-wrapper.sh
```

### 2. Installer le script PowerShell

Copiez `config/chrome-debug.ps1` vers Windows :

```bash
WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
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
      ],
      "env": {
        "CDP_PORT": "9222"
      }
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
Terminal 2 : claude                   → Claude Code avec acces navigateur
Chrome :     lance automatiquement    → Claude voit localhost:3000
```

Claude Code peut alors :
- Modifier votre code
- Capturer un screenshot pour verifier le resultat
- Naviguer dans votre interface pour tester les interactions
- Verifier la console pour les erreurs
- Tout ca sans quitter le terminal

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
  [OK] Mode NAT detecte (host gateway: 172.x.x.1)

[CDP] Test de connexion CDP sur 172.x.x.1:9222
  [OK] Chrome CDP accessible — Chrome/131.x.x.x
  [INFO] WebSocket: ws://172.x.x.1:9222/devtools/browser/...

[TABS] Liste des onglets Chrome
  [OK] 3 onglet(s) detecte(s)

[PS] Verification PowerShell et script de lancement
  [OK] powershell.exe accessible depuis WSL
  [OK] chrome-debug.ps1 trouve

[NPX] Verification de Node.js et npx
  [OK] Node.js installe : v22.x.x
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
│   ├── chrome-devtools-mcp-wrapper.sh  # Wrapper MCP (auto-launch + reseau WSL2)
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

## Troubleshooting

### Le MCP ne se connecte pas a Chrome

1. Lancez le diagnostic :
   ```bash
   ./scripts/check-chrome.sh
   ```
2. Verifiez que Chrome est bien lance avec le port de debug :
   ```bash
   WIN_HOST=$(ip route show default | awk '{print $3}')
   curl http://$WIN_HOST:9222/json/version
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

### Port CDP deja utilise

Utilisez un port different :

```bash
CDP_PORT=9333 ./scripts/launch-chrome.sh
CDP_PORT=9333 claude
```

### Mode mirrored : localhost ne fonctionne pas

Si vous utilisez le mode `networkingMode=mirrored` dans `.wslconfig` et que la connexion ne fonctionne pas, verifiez :

```bash
# Le wrapper detecte automatiquement le mode — forcez le diagnostic :
./scripts/check-chrome.sh
```

## Licence

MIT
