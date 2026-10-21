[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'trial-manifest.json') -Raw | ConvertFrom-Json
$sessionDir=Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'evidence') -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!$sessionDir) { throw 'Start R7 and press F8 first.' }
function Read-Tsv([string]$Name) {
    $result=@{}; Get-Content -LiteralPath (Join-Path $sessionDir.FullName $Name) | ForEach-Object { $kv=$_ -split "`t",2;if ($kv.Count -eq 2) { $result[$kv[0]]=$kv[1] } };return $result
}
$session=Get-Content -LiteralPath (Join-Path $sessionDir.FullName 'session.json') -Raw | ConvertFrom-Json
$native=Read-Tsv 'plane-flight-status.tsv';$request=Read-Tsv 'plane-flight-request.tsv';$coop=Read-Tsv 'coop-status.tsv'
$age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$request.created_unix
if ($age -lt 0 -or $age -ge 100) { throw 'Fresh F8 is required; coordinate F8 on both PCs. Restart both profiles if a previous generation was stopped.' }
if ($native.status -ne 'ready' -or $native.attempted -ne '0' -or $native.module_revision -ne 'r7' -or $native.native_detail -ne 'preflight_verified' -or $native.dispatcher_verified -ne '1' -or $native.stamp -ne $request.stamp) { throw 'Native preflight is not ready or an attempt was consumed.' }
if ($coop.revision -ne 'r7' -or $coop.stamp -ne $native.stamp -or $coop.peer_ready -ne '1' -or $coop.transport_ready -ne '1' -or $coop.stopped -ne '0' -or $coop.local_armed -ne '0') { throw "Peer is not ready: $($coop.detail). Both need F8 in the same supported mission/loadout." }
if ($coop.has_peer -ne '1' -or [uint64]$coop.epoch -eq 0 -or [uint64]$coop.generation -eq 0 -or [uint64]$coop.peer_generation -eq 0 -or [uint64]$coop.peer_age_ms -gt 1000) { throw 'Peer binding or latest state is not fresh.' }
if (((Get-Date)-(Get-Item -LiteralPath (Join-Path $sessionDir.FullName 'coop-status.tsv')).LastWriteTime).TotalSeconds -gt 2) { throw 'Peer status is stale.' }
if ($null -ne $session.exit_code) { throw 'Game exited.' }
$game=Get-Process -Id $session.pid -ErrorAction Stop
if ($game.ProcessName -ne 'AceCombat8') { throw 'Process changed.' }
$modules=@($game.Modules | Where-Object ModuleName -eq 'ac8_plane_coop_r7.dll')
if ($modules.Count -ne 1 -or (Get-FileHash -LiteralPath $modules[0].FileName).Hash -ne $manifest.native_sha256 -or $session.native_probe_sha256 -ne $manifest.native_sha256) { throw 'R7 DLL mismatch.' }
$players=Get-Content -LiteralPath (Join-Path $sessionDir.FullName ('snapshot-'+$native.stamp+'.tsv')) | Where-Object { $_ -like "PlayerController`t*" }
if (!$players -or $players -notmatch 'Mission007' -or $players -notmatch 'PP0023_f14d') { throw 'Mission/F14D not verified.' }
[IO.File]::WriteAllText((Join-Path $sessionDir.FullName 'plane-flight-armed.txt'),$native.stamp,[Text.Encoding]::ASCII)
[ordered]@{revision='r7';stamp=$native.stamp;reviewed=(Get-Date -Format o);pid=$session.pid;epoch=$coop.epoch;generation=$coop.generation;peer_generation=$coop.peer_generation;native_sha256=$manifest.native_sha256;decision='one bounded F7 trial armed after native and peer readiness checks'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDir.FullName 'r7-preflight-review.json') -Encoding UTF8
Write-Output 'ARMED. Both participants press F7 once within 20 seconds. Native motion lasts at most 15 seconds; F9 stops both copies.'
