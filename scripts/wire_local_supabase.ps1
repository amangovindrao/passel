<#
.SYNOPSIS
    Points the backend and the phone build at the local Supabase stack.

.DESCRIPTION
    Reads the running stack's JWT secret and anon key, then writes:
      * paasel-backend/.env       SUPABASE_URL + SUPABASE_JWT_SECRET
      * dart_defines/phone.env    SUPABASE_URL/ANON_KEY + API_BASE_URL on the LAN IP

    The backend has to verify the exact tokens this stack issues, so its
    SUPABASE_URL must match what the apps authenticate against — the issuer
    claim is derived from it and a mismatch reads as "invalid token".

    Local development only.
#>
param([string]$HostIp)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$env:Path = 'C:\Program Files\Docker\Docker\resources\bin;' + $env:Path

function Get-WifiIp {
    $c = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and
        $_.InterfaceAlias -notmatch 'vEthernet|Loopback|Bluetooth'
    }
    $wifi = $c | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|Wireless' } | Select-Object -First 1
    if ($wifi) { return $wifi.IPAddress }
    return ($c | Select-Object -First 1).IPAddress
}

if (-not $HostIp) { $HostIp = Get-WifiIp }
if (-not $HostIp) { throw 'Could not determine a LAN IP. Pass -HostIp.' }

$tmp = Join-Path $env:TEMP 'sb_wire.env'
Push-Location $repo
try {
    cmd /c "npx --yes supabase@latest status -o env > `"$tmp`" 2>nul" | Out-Null
} finally {
    Pop-Location
}
if (-not (Test-Path $tmp)) { throw 'supabase status produced nothing. Is the stack running?' }

$vals = @{}
foreach ($line in Get-Content $tmp) {
    if ($line -match '^([A-Z_]+)="?([^"]*)"?$') { $vals[$Matches[1]] = $Matches[2] }
}
foreach ($key in 'ANON_KEY', 'JWT_SECRET') {
    if (-not $vals.ContainsKey($key)) { throw "supabase status did not report $key" }
}

# --- backend ---
# 127.0.0.1 on purpose: the server talks to Supabase over loopback. Only the
# issuer string has to agree with what the apps used, and GoTrue derives that
# from its own configured URL, not from how a client reached it.
$supabaseForBackend = 'http://127.0.0.1:54321'
$backendEnv = Join-Path $repo 'paasel-backend\.env'
$content = Get-Content $backendEnv -Raw
$content = $content -replace 'SUPABASE_URL=[^\r\n]*', "SUPABASE_URL=$supabaseForBackend"
$content = $content -replace 'SUPABASE_JWT_SECRET=[^\r\n]*', "SUPABASE_JWT_SECRET=$($vals['JWT_SECRET'])"
Set-Content $backendEnv -Value $content -NoNewline

# --- phone build ---
$phoneEnv = Join-Path $repo 'dart_defines\phone.env'
$content = Get-Content $phoneEnv -Raw
$content = $content -replace 'API_BASE_URL=[^\r\n]*', "API_BASE_URL=http://${HostIp}:8000"
$content = $content -replace 'SUPABASE_URL=[^\r\n]*', "SUPABASE_URL=http://${HostIp}:54321"
$content = $content -replace 'SUPABASE_ANON_KEY=[^\r\n]*', "SUPABASE_ANON_KEY=$($vals['ANON_KEY'])"
Set-Content $phoneEnv -Value $content -NoNewline

Write-Host 'wired:' -ForegroundColor Green
Write-Host "  backend  SUPABASE_URL      = $supabaseForBackend"
Write-Host "  backend  SUPABASE_JWT_SECRET = <$($vals['JWT_SECRET'].Length) chars>"
Write-Host "  phone    API_BASE_URL      = http://${HostIp}:8000"
Write-Host "  phone    SUPABASE_URL      = http://${HostIp}:54321"
Write-Host "  phone    SUPABASE_ANON_KEY = <$($vals['ANON_KEY'].Length) chars>"
