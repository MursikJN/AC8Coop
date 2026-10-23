# Launcher failure-path tests. No Launch switch is passed; no process is started.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $repo ('build/mission6-preflight-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'runtime') -Force|Out-Null
foreach($name in @('Start-Mission6Capture.ps1','Coop-Kit.ps1','Coop-LabStorage.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixture}
function Reject($Manifest,[string]$Expected){
 $Manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $fixture 'capture-profile.json') -Encoding UTF8
 $message='';try{& (Join-Path $fixture 'Start-Mission6Capture.ps1') -ProfileRoot $fixture}catch{$message=$_.Exception.Message}
 if(!$message.Contains($Expected)){throw ('Wrong rejection: '+$message+' expected '+$Expected)}
 Write-Output ('PASS: '+$Expected)
}
$cfg=[ordered]@{format='bad';game_sha256='51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f';files=@()}
Reject $cfg 'Unsupported capture profile'
$cfg.format='ac8-mission6-capture-v1';Reject $cfg 'Missing capture manifest entry'
$cfg.files=@(@{path='../escape';sha256='0'});Reject $cfg 'Invalid profile manifest path'
$cfg.files=@(@{path='Start-Mission6Capture.ps1';sha256='0'});Reject $cfg 'Profile changed'
# Keep the tiny fixture for inspection; no recursive deletion.
Write-Output ('Launcher rejection tests PASS; fixture: '+$fixture)
