[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GameDirectory,
    [string]$OutputRoot = '',
    [string]$UE4SSPackage = '',
    [string]$FlightDll = ''
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$OutputRoot) { $OutputRoot = Join-Path $repo 'profiles\ac8-build25201480-r6' }
if (!$UE4SSPackage) { $UE4SSPackage = Join-Path $repo 'packages\ue4ss-3.0.1-1181-g83330635' }
if (!$FlightDll) { $FlightDll = Join-Path $repo 'build\plane-flight-r6\ac8_plane_flight_probe_r6.dll' }
$gameDir = [IO.Path]::GetFullPath($GameDirectory)
$expectedGame = '51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F'
$expectedProxy = '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB'
if ((Get-FileHash -LiteralPath (Join-Path $gameDir 'AceCombat8.exe')).Hash -ne $expectedGame) { throw 'Unsupported game build.' }
if ((Get-FileHash -LiteralPath (Join-Path $UE4SSPackage 'dwmapi.dll')).Hash -ne $expectedProxy) { throw 'UE4SS proxy differs from the reviewed build.' }
# Launcher resolves packages relative to profiles/<profile>. Refuse a layout it cannot use.
$output = [IO.Path]::GetFullPath($OutputRoot)
if ((Split-Path (Split-Path $output -Parent) -Parent) -ne $repo) { throw 'OutputRoot must be a profile directly below this repository profiles directory.' }
if ((Split-Path $output -Parent) -ne (Join-Path $repo 'profiles')) { throw 'OutputRoot must be below profiles.' }
$expectedPackage = Join-Path $repo 'packages\ue4ss-3.0.1-1181-g83330635'
if ([IO.Path]::GetFullPath($UE4SSPackage) -ne $expectedPackage) { throw 'Put the pinned package at packages\ue4ss-3.0.1-1181-g83330635 first.' }
$flightHash = (Get-FileHash -LiteralPath $FlightDll).Hash
$runtimeSource = Join-Path $UE4SSPackage 'ue4ss'
$runtimeHash = (Get-FileHash -LiteralPath (Join-Path $runtimeSource 'UE4SS.dll')).Hash
if (Test-Path -LiteralPath $output) { throw 'Profile already exists; use a new OutputRoot rather than overwrite a previous trial.' }
$runtime = Join-Path $output 'runtime'
$modScripts = Join-Path $runtime 'Mods\AC8CoopRecon\Scripts'
New-Item -ItemType Directory -Path $modScripts -Force | Out-Null
foreach ($file in @('UE4SS.dll','UE4SS-settings.ini','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $runtimeSource $file) -Destination $runtime
}
Copy-Item -LiteralPath (Join-Path $runtimeSource 'Mods\shared') -Destination (Join-Path $runtime 'Mods') -Recurse
Copy-Item -LiteralPath $FlightDll -Destination (Join-Path $runtime 'ac8_plane_flight_probe_r6.dll')
foreach ($file in @('main.lua','plane_flight_probe.lua')) {
    Copy-Item -LiteralPath (Join-Path $repo ('probe\AC8CoopRecon\Scripts\' + $file)) -Destination $modScripts
}
[IO.File]::WriteAllText((Join-Path $runtime 'Mods\mods.txt'), "AC8CoopRecon : 1`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $runtime 'Mods\mods.json'), '[{"mod_name":"AC8CoopRecon","mod_enabled":true}]', [Text.Encoding]::ASCII)
foreach ($file in @('Launch-Recon.ps1','Remove-ReconLoader.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $output
}
# Freeze the reviewed artifact hashes when preparing, never derive trust from a file at launch.
$escapedGame = $gameDir.Replace("'", "''")
$wrapper = @'
[CmdletBinding()]
param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'runtime\UE4SS.dll')).Hash -ne '__RUNTIME_HASH__') { throw 'UE4SS runtime hash mismatch.' }
& (Join-Path $PSScriptRoot 'Launch-Recon.ps1') -PlaneFlight -PlaneFlightHash '__FLIGHT_HASH__' -GameDirectory '__GAME_DIR__' -ValidateOnly:$ValidateOnly
'@
$wrapper = $wrapper.Replace('__RUNTIME_HASH__', $runtimeHash).Replace('__FLIGHT_HASH__', $flightHash).Replace('__GAME_DIR__', $escapedGame)
[IO.File]::WriteAllText((Join-Path $output 'Start-R6.ps1'), $wrapper, [Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $output 'Start-R6.cmd'), "@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Start-R6.ps1`"`r`npause`r`n", [Text.Encoding]::ASCII)
$manifest = [ordered]@{revision='r6';game_sha256=$expectedGame;native_sha256=$flightHash;runtime_sha256=$runtimeHash;proxy_sha256=$expectedProxy;game_directory=$gameDir;live_verified=$false}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'trial-manifest.json') -Encoding UTF8
& (Join-Path $output 'Start-R6.ps1') -ValidateOnly
Write-Output "Prepared R6 profile: $output. No launch or game edits."
