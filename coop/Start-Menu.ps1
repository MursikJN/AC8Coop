[CmdletBinding()]
param([string]$GameDirectory='', [switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'trial-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.revision -notin @('r8','r9','r10')) { throw 'Not a supported main-menu profile.' }
foreach ($entry in $manifest.files) {
    $target=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $entry.path))
    if (!$target.StartsWith($PSScriptRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid manifest path.' }
    if ((Get-FileHash -LiteralPath $target).Hash -ne $entry.sha256) { throw "Profile hash mismatch: $($entry.path)" }
}
$state=Join-Path $PSScriptRoot 'state';$settingsFile=Join-Path $state 'launcher-settings.json'
if (!$GameDirectory -and (Test-Path -LiteralPath $settingsFile)) { $GameDirectory=(Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json).game_directory }
if (!$GameDirectory) { $GameDirectory=Read-Host 'Path to ACE COMBAT 8 folder' }
$candidate=[IO.Path]::GetFullPath($GameDirectory.Trim().Trim('"'));$gameDir=$null
if ([IO.File]::Exists($candidate)) { $candidate=Split-Path $candidate -Parent }
foreach ($suffix in @('','Game\Binaries\Win64','Binaries\Win64')) {
    $path=if ($suffix) { Join-Path $candidate $suffix } else { $candidate }
    if ([IO.File]::Exists((Join-Path $path 'AceCombat8.exe'))) { $gameDir=$path;break }
}
if (!$gameDir) { throw 'AceCombat8.exe not found.' }
if (!$ValidateOnly) {
    New-Item -ItemType Directory -Force -Path $state | Out-Null
    @{game_directory=$gameDir} | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
}
$lobbyArgs=@{}
if ($manifest.revision -in @('r9','r10')) { $lobbyArgs=@{CoopLobby=$true;LobbyHash=$manifest.lobby_sha256;MenuRouteHash=$manifest.menu_route_sha256} }
if ($manifest.revision -eq 'r10') { $lobbyArgs.Continuous=$true }
& (Join-Path $PSScriptRoot 'Launch-Recon.ps1') -PlaneFlight -CoopFlight -CoopMenu -PlaneFlightHash $manifest.native_sha256 -GameDirectory $gameDir -ValidateOnly:$ValidateOnly @lobbyArgs
