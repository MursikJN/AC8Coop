[CmdletBinding()]
param([string]$GameDirectory='', [string]$HostSteamId='', [switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'native-trial-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $manifest.files) {
    $target=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $entry.path))
    if (!$target.StartsWith($PSScriptRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid manifest path.' }
    if ((Get-FileHash -LiteralPath $target).Hash -ne $entry.sha256) { throw "Profile hash mismatch: $($entry.path)" }
}
$state=Join-Path $PSScriptRoot 'state';$settings=Join-Path $state 'native-guest-settings.json'
if (Test-Path -LiteralPath $settings) {
    $saved=Get-Content -LiteralPath $settings -Raw|ConvertFrom-Json
    if (!$GameDirectory) { $GameDirectory=$saved.game_directory }
    if (!$HostSteamId) { $HostSteamId=$saved.host_steam_id }
}
if (!$GameDirectory) { $GameDirectory=Read-Host 'Path to ACE COMBAT 8 folder' }
$candidate=[IO.Path]::GetFullPath($GameDirectory.Trim().Trim('"'));$gameDir=$null
if ([IO.File]::Exists($candidate)) { $candidate=Split-Path $candidate -Parent }
foreach ($suffix in @('','Game\Binaries\Win64','Binaries\Win64')) {
    $path=if ($suffix) { Join-Path $candidate $suffix } else { $candidate }
    if ([IO.File]::Exists((Join-Path $path 'AceCombat8.exe'))) { $gameDir=$path;break }
}
if (!$gameDir) { throw 'AceCombat8.exe not found.' }
if (!$HostSteamId) { $HostSteamId=Read-Host 'Host SteamID64 (17 digits)' }
if ($HostSteamId -notmatch '^7656119[0-9]{10}$') { throw 'Invalid host SteamID64.' }
if (!$ValidateOnly) {
    New-Item -ItemType Directory -Force -Path $state|Out-Null
    @{game_directory=$gameDir;host_steam_id=$HostSteamId}|ConvertTo-Json|Set-Content -LiteralPath $settings -Encoding UTF8
}
$previous=$env:AC8_NATIVE_HOST_STEAM_ID
try {
    $env:AC8_NATIVE_HOST_STEAM_ID=$HostSteamId
    & (Join-Path $PSScriptRoot 'Launch-Recon.ps1') -GameDirectory $gameDir -ValidateOnly:$ValidateOnly
} finally { $env:AC8_NATIVE_HOST_STEAM_ID=$previous }
if (!$ValidateOnly) { & (Join-Path $PSScriptRoot 'Collect-NativeLogs.ps1') }
