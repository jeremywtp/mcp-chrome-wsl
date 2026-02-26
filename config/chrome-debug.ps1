# chrome-debug.ps1
# Lance Google Chrome avec le port de debug distant (CDP) pour MCP Chrome DevTools
# Configure aussi le portproxy v4tov6 pour que WSL2 puisse acceder a Chrome
# Usage : powershell.exe -ExecutionPolicy Bypass -File C:\Users\<USER>\scripts\chrome-debug.ps1

param(
    [int]$Port = 9222,
    [string]$ProfileName = "claude-debug"
)

$ChromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$UserDataDir = "$env:LOCALAPPDATA\Google\Chrome\UserData-$ProfileName"

# ── Portproxy WSL2 : forward IPv4 0.0.0.0:9222 -> IPv6 [::1]:9222 ──
$proxyExists = netsh interface portproxy show v4tov6 2>$null | Select-String "$Port"
if (-not $proxyExists) {
    Write-Host "[INFO] Configuration du portproxy v4tov6 pour WSL2..." -ForegroundColor Cyan
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        netsh interface portproxy add v4tov6 listenaddress=0.0.0.0 listenport=$Port connectaddress=::1 connectport=$Port | Out-Null
        $fwRule = Get-NetFirewallRule -DisplayName "Chrome CDP Debug (WSL)" -ErrorAction SilentlyContinue
        if (-not $fwRule) {
            New-NetFirewallRule -DisplayName "Chrome CDP Debug (WSL)" -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow | Out-Null
        }
        Write-Host "[OK] Portproxy v4tov6 configure (0.0.0.0:$Port -> [::1]:$Port)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Portproxy manquant. Elevation admin..." -ForegroundColor Yellow
        Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -Command `"netsh interface portproxy add v4tov6 listenaddress=0.0.0.0 listenport=$Port connectaddress=::1 connectport=$Port; New-NetFirewallRule -DisplayName 'Chrome CDP Debug (WSL)' -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow -ErrorAction SilentlyContinue`""
        Write-Host "[OK] Portproxy v4tov6 configure via elevation admin" -ForegroundColor Green
    }
} else {
    Write-Host "[OK] Portproxy WSL2 deja en place" -ForegroundColor Green
}

# ── Chrome ──
$chromeListening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Where-Object {
    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
    $proc.ProcessName -eq "chrome"
}
if ($chromeListening) {
    Write-Host "[OK] Chrome debug deja actif sur le port $Port" -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $ChromePath)) {
    Write-Host "[ERREUR] Chrome non trouve : $ChromePath" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Lancement de Chrome avec debug sur le port $Port..." -ForegroundColor Cyan
Write-Host "[INFO] Profil dedie : $UserDataDir" -ForegroundColor Cyan

Start-Process -FilePath $ChromePath -ArgumentList @(
    "--remote-debugging-port=$Port",
    "--user-data-dir=$UserDataDir",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-allow-origins=*"
)

# Attendre que Chrome ecoute
$maxRetries = 15
$retryCount = 0
do {
    Start-Sleep -Milliseconds 500
    $retryCount++
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Where-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        $proc.ProcessName -eq "chrome"
    }
} while (-not $conn -and $retryCount -lt $maxRetries)

if ($conn) {
    Write-Host "[OK] Chrome debug actif sur http://localhost:$Port" -ForegroundColor Green
    Write-Host "[OK] Accessible depuis WSL via portproxy" -ForegroundColor Green
} else {
    Write-Host "[WARN] Chrome lance mais le port $Port n'est pas encore ouvert." -ForegroundColor Yellow
}
