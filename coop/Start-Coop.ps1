[CmdletBinding()]
param([ValidateSet('host','guest')][string]$Role='host', [string]$PeerSteamId='', [string]$GameDirectory='', [switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$manifest=Get-Content -LiteralPath (Join-Path $root 'trial-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.revision -ne 'r7') { throw 'Not an R7 profile.' }
foreach ($entry in $manifest.files) {
    $target=[IO.Path]::GetFullPath((Join-Path $root $entry.path))
    if (!$target.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid manifest path.' }
    if ((Get-FileHash -LiteralPath $target).Hash -ne $entry.sha256) { throw "Profile hash mismatch: $($entry.path)" }
}
$state=Join-Path $root 'state';$settingsFile=Join-Path $state 'launcher-settings.json';$settings=@{}
if (Test-Path -LiteralPath $settingsFile) { $loaded=Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json; foreach ($p in $loaded.PSObject.Properties) { $settings[$p.Name]=$p.Value } }
if (!$GameDirectory) { $GameDirectory=$settings.game_directory }
if (!$GameDirectory) { $GameDirectory=Read-Host 'Path to ACE COMBAT 8 folder' }
$candidate=[IO.Path]::GetFullPath($GameDirectory.Trim().Trim('"'))
if ([IO.File]::Exists($candidate)) { $candidate=Split-Path $candidate -Parent }
$gameDir=$null
foreach ($suffix in @('','Game\Binaries\Win64','Binaries\Win64')) {
    $path=if ($suffix) { Join-Path $candidate $suffix } else { $candidate }
    if ([IO.File]::Exists((Join-Path $path 'AceCombat8.exe'))) { $gameDir=$path;break }
}
if (!$gameDir) { throw 'AceCombat8.exe not found.' }
if (!$PeerSteamId) { $PeerSteamId=$settings[$Role+'_peer'] }
if (!$PeerSteamId) { $PeerSteamId=Read-Host 'OTHER participant SteamID64 (17 digits)' }
$PeerSteamId=$PeerSteamId.Trim()
if ($PeerSteamId -notmatch '^[0-9]{17}$') { throw 'Invalid SteamID64.' }
if (!$ValidateOnly) {
    New-Item -ItemType Directory -Force -Path $state | Out-Null
    $settings.game_directory=$gameDir;$settings[$Role+'_peer']=$PeerSteamId
    $settings | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
}
Write-Output "R7 ${Role}: both players use mission 6 F-14D, identical loadout. F8 on BOTH; wait for peer_ready=1, Review-And-Arm, then F7 on BOTH within 20 seconds. F9 stops the trial."
& (Join-Path $root 'Launch-Recon.ps1') -PlaneFlight -CoopFlight -Role $Role -PeerSteamId $PeerSteamId -PlaneFlightHash $manifest.native_sha256 -GameDirectory $gameDir -ValidateOnly:$ValidateOnly
