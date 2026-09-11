<#
.SYNOPSIS
    Builds installable APKs for all three Paasel apps.

.DESCRIPTION
    Detects this machine's Wi-Fi address, writes it into dart_defines/phone.env
    along with the local Supabase anon key, then builds one APK per app and
    copies them to build/apk/ at the repo root.

    Release builds, split per ABI. This used to build debug and the APKs came
    out at 134 MB each, for two compounding reasons: a debug build ships the
    Dart VM plus JIT-compiled kernel and skips tree-shaking, and a non-split
    build bundles native libraries for every architecture — arm64, armv7 and
    x86_64 — when a phone can only ever use one. Release + split is roughly a
    six-fold reduction and changes nothing about how it installs.

    Still signed with the standard debug key, because android/app/build.gradle.kts
    points the release signing config at it. That is what keeps these
    sideloadable with no keystore setup, and also why they are not shippable.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/build_apks.ps1

.EXAMPLE
    # Skip the config rewrite and just rebuild
    powershell -ExecutionPolicy Bypass -File scripts/build_apks.ps1 -SkipConfig

.EXAMPLE
    # Debug build, when a stack trace matters more than size
    powershell -ExecutionPolicy Bypass -File scripts/build_apks.ps1 -Debug
#>
param(
    [switch]$SkipConfig,
    [string]$HostIp,
    [string]$AnonKey,
    [switch]$Debug
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repo 'dart_defines\phone.env'
$outDir = Join-Path $repo 'build\apk'

function Get-WifiIp {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notmatch 'vEthernet|Loopback|Bluetooth'
        }
    $wifi = $candidates | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|Wireless' } |
        Select-Object -First 1
    if ($wifi) { return $wifi.IPAddress }
    return ($candidates | Select-Object -First 1).IPAddress
}

function Get-SupabaseAnonKey {
    Push-Location $repo
    try {
        $status = npx --yes supabase@latest status -o env 2>$null | Out-String
    } finally {
        Pop-Location
    }
    foreach ($line in ($status -split "`r?`n")) {
        if ($line -match '^ANON_KEY="?([^"]+)"?$') { return $Matches[1] }
    }
    return $null
}

if (-not $SkipConfig) {
    if (-not $HostIp) { $HostIp = Get-WifiIp }
    if (-not $HostIp) { throw 'Could not determine a LAN IP. Pass -HostIp explicitly.' }

    if (-not $AnonKey) { $AnonKey = Get-SupabaseAnonKey }
    if (-not $AnonKey) {
        Write-Warning 'Could not read the Supabase anon key. Is `npx supabase start` running?'
        Write-Warning 'Leaving the existing value in phone.env untouched.'
    }

    Write-Host "host ip  : $HostIp" -ForegroundColor Cyan
    $content = Get-Content $envFile -Raw
    $content = $content -replace 'API_BASE_URL=http://[^\r\n]+', "API_BASE_URL=http://${HostIp}:8000"
    $content = $content -replace 'SUPABASE_URL=http://[^\r\n]+', "SUPABASE_URL=http://${HostIp}:54321"
    if ($AnonKey) {
        $content = $content -replace 'SUPABASE_ANON_KEY=[^\r\n]+', "SUPABASE_ANON_KEY=$AnonKey"
        Write-Host 'anon key : resolved from supabase status' -ForegroundColor Cyan
    }
    Set-Content -Path $envFile -Value $content -NoNewline
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$apps = @(
    @{ Name = 'customer_app'; Label = 'Paasel' },
    @{ Name = 'shop_app';     Label = 'Paasel Shop' },
    @{ Name = 'delivery_app'; Label = 'Paasel Rider' }
)

$mode = if ($Debug) { 'debug' } else { 'release' }
Write-Host "mode     : $mode" -ForegroundColor Cyan

# arm64 first: it is what every phone from about 2016 on actually runs, so it
# becomes <app>.apk. armv7 is kept alongside for genuinely old hardware. x86_64
# is emulator-only and not worth copying.
$abiPreference = @('arm64-v8a', 'armeabi-v7a')

$built = @()
$failed = @()
foreach ($app in $apps) {
    $dir = Join-Path $repo "apps\$($app.Name)"
    $apkDir = Join-Path $dir 'build\app\outputs\flutter-apk'
    Write-Host "`n=== building $($app.Label) ===" -ForegroundColor Yellow

    # Clear previous artefacts so a failed build cannot be mistaken for a
    # successful one just because a stale APK is still sitting there.
    Remove-Item (Join-Path $apkDir '*.apk') -Force -ErrorAction SilentlyContinue

    $log = Join-Path $env:TEMP "paasel_build_$($app.Name).log"
    $buildArgs = @("--$mode", "--dart-define-from-file=$envFile")
    if (-not $Debug) { $buildArgs += '--split-per-abi' }

    Push-Location $dir
    try {
        # ErrorActionPreference is Stop for this script, and `flutter build`
        # writes ordinary notices to stderr — the Android x86 deprecation warning
        # among them. Left as Stop, PowerShell turns that notice into a
        # terminating NativeCommandError and the whole run dies after the first
        # app with no explanation. So the exit code is the success signal here,
        # not the presence of stderr.
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & flutter build apk @buildArgs *>&1 |
            Tee-Object -FilePath $log |
            Select-String -Pattern 'Built build|FAILURE|error:|Execution failed' |
            ForEach-Object { Write-Host "  $_" }
        $code = $LASTEXITCODE
        $ErrorActionPreference = $previous
    } finally {
        Pop-Location
    }

    if ($code -ne 0) {
        Write-Host "  FAILED (exit $code). Full log: $log" -ForegroundColor Red
        $failed += $app.Name
        continue
    }

    # A debug build produces one fat APK; a split release produces one per ABI.
    $produced = if ($Debug) {
        @(Join-Path $apkDir 'app-debug.apk')
    } else {
        $abiPreference | ForEach-Object { Join-Path $apkDir "app-$_-release.apk" }
    }
    $present = @($produced | Where-Object { Test-Path $_ })

    if ($present.Count -eq 0) {
        Write-Host "  FAILED: no APK produced. Log: $log" -ForegroundColor Red
        $failed += $app.Name
        continue
    }

    for ($i = 0; $i -lt $present.Count; $i++) {
        # The first (arm64, or the debug fat APK) gets the plain name so there is
        # no ambiguity about which one to install.
        $suffix = if ($i -eq 0) { '' } else { '-armv7' }
        $dest = Join-Path $outDir "$($app.Name)$suffix.apk"
        Copy-Item $present[$i] $dest -Force
        $built += [pscustomobject]@{
            App = $app.Label
            File = "build/apk/$($app.Name)$suffix.apk"
            MB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        }
    }
}

Write-Host "`n=== done ===" -ForegroundColor Green
$built | Format-Table -AutoSize
Write-Host "APKs are in $outDir"
Write-Host 'Install the plain <app>.apk — it is the arm64 build every current phone uses.'
Write-Host 'The -armv7 files are only for pre-2016 hardware.'

if ($failed.Count -gt 0) {
    throw "did not build: $($failed -join ', ')"
}
