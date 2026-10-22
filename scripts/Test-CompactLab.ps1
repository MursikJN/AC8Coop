[CmdletBinding()]
param([string]$Kit='')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if(!$Kit){$Kit=Join-Path $repo 'profiles/ac8-steam-coop-r31'}
. (Join-Path $PSScriptRoot 'Coop-Kit.ps1')
$script:checks=0
function Check([bool]$Ok,[string]$Why){$script:checks++;if(!$Ok){throw $Why}}
function Refuse([scriptblock]$Action,[string]$Pattern=''){
 $errorFound=$null;try{& $Action|Out-Null}catch{$errorFound=$_}
 Check ([bool]$errorFound) 'Expected refusal did not occur'
 if($Pattern){Check ($errorFound.Exception.Message -like ('*'+$Pattern+'*')) ('Wrong refusal: '+$errorFound.Exception.Message)}
}
$scratch=Join-Path $repo ('build/compact-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch|Out-Null
$fixture=Join-Path $scratch 'kit';Copy-Item -LiteralPath $Kit -Destination $fixture -Recurse
$source=Join-Path $scratch 'source with spaces';$sourceBin=Join-Path $source 'Game/Binaries/Win64';$sourceSteam=Join-Path $source 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64';$paks=Join-Path $source 'Game/Content/Paks'
foreach($d in @($sourceBin,$sourceSteam,$paks)){New-Item -ItemType Directory -Force -Path $d|Out-Null}
[IO.File]::WriteAllText((Join-Path $sourceBin 'AceCombat8.exe'),'FAKE GAME, NEVER EXECUTED')
[IO.File]::WriteAllText((Join-Path $sourceSteam 'steam_api64.dll'),'FAKE STEAM, NEVER LOADED')
foreach($ext in @('pak','utoc','ucas','sig')){[IO.File]::WriteAllText((Join-Path $paks ('fixture.'+$ext)),('fixture bytes '+$ext))}
[IO.File]::WriteAllText((Join-Path $source 'ordinary.txt'),'ordinary independently copied file')
function Source-Snapshot {return (@(Get-ChildItem -LiteralPath $source -Recurse -File|Sort-Object FullName|ForEach-Object {$_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash+'|'+$_.LastWriteTimeUtc.Ticks+'|'+[int]$_.Attributes}) -join "`n")}
$before=Source-Snapshot
$mp=Join-Path $fixture 'lobby-manifest.json';$m=Get-Content -LiteralPath $mp -Raw|ConvertFrom-Json
$m.game_sha256=(Get-FileHash -LiteralPath (Join-Path $sourceBin 'AceCombat8.exe')).Hash;$m.steam_sha256=(Get-FileHash -LiteralPath (Join-Path $sourceSteam 'steam_api64.dll')).Hash
$m|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $mp -Encoding UTF8
$plan=& (Join-Path $fixture 'Prepare-CoopLab.ps1') -SourceGameDirectory $source -PlanOnly|ConvertFrom-Json
Check ($plan.archive_count -eq 4 -and $plan.shared_bytes -gt 0 -and $plan.copy_bytes -lt $plan.source_bytes) 'Wrong compact plan'
Check (!(Test-Path -LiteralPath (Join-Path $fixture 'lab-game'))) 'PlanOnly wrote lab'
& (Join-Path $fixture 'Prepare-CoopLab.ps1') -SourceGameDirectory $source|Out-Null
$bin=Test-CoopLab -Root $fixture -Manifest $m
$markerPath=Join-Path $fixture 'lab-game/.ac8-coop-lab.json';$markerText=[IO.File]::ReadAllText($markerPath);$marker=$markerText|ConvertFrom-Json
Check ($marker.storage_mode -eq 'compact' -and $marker.archives.Count -eq 4) 'Wrong storage marker'
Check ((Source-Snapshot) -eq $before) 'Preparation modified source bytes/attributes/time'
$linked=Join-Path $fixture 'lab-game/Game/Content/Paks/fixture.pak';$original=Join-Path $paks 'fixture.pak'
Check ((Get-Item -LiteralPath $linked -Force).LinkType -eq 'SymbolicLink') 'Not a file symlink'
Check ([IO.File]::ReadAllText($linked) -eq [IO.File]::ReadAllText($original)) 'Cannot read shared bytes'
Check ([IO.File]::ReadAllText((Join-Path $fixture 'lab-game/ordinary.txt')) -eq 'ordinary independently copied file') 'Ordinary file not copied'
[IO.File]::WriteAllText((Join-Path $fixture 'lab-game/ordinary.txt'),'local writable copy')
Check ([IO.File]::ReadAllText((Join-Path $source 'ordinary.txt')) -eq 'ordinary independently copied file') 'Copied-file write reached original'
$guard=$null
try{
 $null=Test-CoopLab -Root $fixture -Manifest $m -ArchiveGuard ([ref]$guard)
 Check ($guard.ArchiveCount -eq 4 -and $guard.Streams.Count -eq 8) 'Launch guard did not retain all handles'
 foreach($path in @($original,$linked)){
  Refuse {$f=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$f.Dispose()}
 }
 Refuse {[IO.File]::Delete($original)}
 $f=[IO.File]::Open($original,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);$f.Dispose();Check $true 'Compatible read failed'
 Check ((Source-Snapshot) -eq $before) 'Guard altered source'
}finally{Close-CoopArchiveGuard $guard}
$f=[IO.File]::Open($original,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$f.Dispose();Check $true 'Guard failed to release'
# Wrong symlink target must refuse and close partially acquired locks.
$foreign=Join-Path $scratch 'foreign.pak';[IO.File]::WriteAllText($foreign,'foreign')
[IO.File]::Delete($linked);New-CoopArchiveLink -Link $linked -Original $foreign
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'target mismatch'
$f=[IO.File]::Open($original,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$f.Dispose();Check $true 'Refusal leaked archive handle'
[IO.File]::Delete($linked);New-CoopArchiveLink -Link $linked -Original $original
# Neither a copied archive replacing the link nor a directory junction is allowed.
[IO.File]::Delete($linked);Copy-Item -LiteralPath $original -Destination $linked
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'plain file'
[IO.File]::Delete($linked);New-CoopArchiveLink -Link $linked -Original $original
$junction=Join-Path $fixture 'lab-game/Game/Content/unexpected'
New-Item -ItemType Junction -Path $junction -Value $paks|Out-Null
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'Unexpected link'
[IO.Directory]::Delete($junction)
# A normal-looking hardlink to the source executable must also be refused.
$exe=Join-Path $bin 'AceCombat8.exe';[IO.File]::Delete($exe)
New-Item -ItemType HardLink -Path $exe -Value (Join-Path $sourceBin 'AceCombat8.exe')|Out-Null
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'Hardlink'
[IO.File]::Delete($exe);Copy-Item -LiteralPath (Join-Path $sourceBin 'AceCombat8.exe') -Destination $exe
$bad=$markerText|ConvertFrom-Json;$bad.archives[0].path='../../escape.pak';$bad|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $markerPath -Encoding UTF8
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'archive list'
[IO.File]::WriteAllText($markerPath,$markerText)
$info=Get-Item -LiteralPath $original;$ticks=$info.LastWriteTimeUtc.Ticks;$bytes=[IO.File]::ReadAllBytes($original)
[IO.File]::AppendAllText($original,'fake source update')
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'Source archive changed'
[IO.File]::WriteAllBytes($original,$bytes);[IO.File]::SetLastWriteTimeUtc($original,[DateTime]::new($ticks,[DateTimeKind]::Utc))
& (Join-Path $fixture 'Start-SteamLobby.ps1') -ValidateOnly -Role host|Out-Null
Check (!(Test-Path -LiteralPath (Join-Path $bin 'dwmapi.dll'))) 'ValidateOnly installed loader'
Check (!(Test-Path -LiteralPath (Join-Path $fixture 'evidence'))) 'ValidateOnly started session'
Check ((Source-Snapshot) -eq $before) 'Source fixture changed after checks'
# Missing lab must expose the actual actionable message rather than ScriptHalted.
$empty=Join-Path $scratch 'unprepared';Copy-Item -LiteralPath $Kit -Destination $empty -Recurse
Refuse {& (Join-Path $empty 'Start-SteamLobby.ps1') -ValidateOnly -Role host} 'Run Prepare-Lab.cmd'
$report=Get-ChildItem -LiteralPath (Join-Path $empty 'reports') -Filter 'launch-failure-*.json'|Select-Object -First 1
Check ((Get-Content -LiteralPath $report.FullName -Raw|ConvertFrom-Json).error -like '*Run Prepare-Lab.cmd*') 'Original failure missing from report'
Write-Output ("PASS: $script:checks compact links, read/write/delete guard, tamper, isolation and error-report checks. Fake files only; no game launched. Fixture: $scratch")
