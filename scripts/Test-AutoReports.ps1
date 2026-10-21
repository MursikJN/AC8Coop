# Virtual-time launcher observer + real ZIP collection; never starts a game.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Auto-Reports.ps1')
. (Join-Path $PSScriptRoot 'Session-Diagnostics.ps1')
$root=Join-Path $repo ('build/auto-reports-test-'+[Guid]::NewGuid().ToString('N'))
$session=Join-Path $root 'evidence/session-fixture';$mod=Join-Path $session 'mod'
New-Item -ItemType Directory -Force -Path $mod|Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'coop/Collect-CoopLogs.ps1') -Destination $root
@{role='host';revision='r29-debug2-development';started=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding UTF8
$script:checks=0
function Assert-Auto([bool]$Condition,[string]$Message){$script:checks++;if(!$Condition){throw $Message}}
function New-State {New-CoopAutoReportState -Root $root -Session $session -UserSaved (Join-Path $root 'userdata/Saved') -NowMs 0}
function Summary([long]$Sequence,[string]$ErrorText='',[int]$Phase=0,[bool]$Active=$true){
 @{format='ac8-diagnostic-summary-v1';sequence=$Sequence;updated_unix=$Sequence;last_state=@{phase=[string]$Phase;generation='1';active=$Active;error=$ErrorText}}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $mod 'diagnostics-summary.json') -Encoding UTF8
}
function Native([long]$Heartbeat,[int]$Phase=0){
 [IO.File]::WriteAllText((Join-Path $mod 'shared-session-status.tsv'),"format`tac8-session-status-v3`nconfig_token`t123`nheartbeat`t$Heartbeat`nphase`t$Phase`ngeneration`t1`nstop_reason`t3`n")
}
$script:captures=@()
$capture={param($state,$file,$reason)$script:captures+=@{file=$file;reason=$reason};return (Join-Path $root $file)}
$state=New-State;Summary 1;Native 1;Update-CoopAutoReports $state 0 $capture
Assert-Auto ($state.Captures -eq 0) 'Collector ran at boot'
Update-CoopAutoReports $state 10001 $capture
Assert-Auto ($state.Captures -eq 1 -and $script:captures[-1].reason -eq 'lua_observation_stalled') 'No report on stalled Lua'
Update-CoopAutoReports $state 11000 $capture
Assert-Auto ($state.Captures -eq 1) 'Persistent stall spammed reports'
Summary 2;Native 2;Update-CoopAutoReports $state 12000 $capture
Summary 3 'adapter failed' 6;Native 3;Update-CoopAutoReports $state 13000 $capture
Assert-Auto ($state.PendingIssue -like 'reported_error*' -and $state.Captures -eq 1) 'Incident cooldown lost pending error'
Summary 4;Native 4;Update-CoopAutoReports $state 26000 $capture
Assert-Auto ($state.Captures -eq 2 -and !$state.PendingIssue) 'Recovered transient error was not archived'
$state=New-State;Summary 1;Native 1;Update-CoopAutoReports $state 0 $capture
Summary 2;Update-CoopAutoReports $state 10001 $capture
Assert-Auto ($state.Captures -eq 1 -and $state.CaptureReason -eq 'native_observation_stalled') 'Worker stall missed while Lua is alive'
$state=New-State;Summary 3 '' 0 $false;Native 3;Update-CoopAutoReports $state 0 $capture
Summary 4 '' 0 $false;Update-CoopAutoReports $state 10001 $capture
Assert-Auto ($state.Captures -eq 0) 'Idle lobby required a worker'
$state=New-State;Summary 5;Native 5;Update-CoopAutoReports $state 0 $capture
Summary 6 '' 8;Native 6 8;Update-CoopAutoReports $state 1000 $capture
Assert-Auto ($state.Captures -eq 1 -and $state.CaptureReason -like 'session_stopped*') 'Stop report missed'
$state=New-State;Summary 1;Native 1
[IO.File]::WriteAllText((Join-Path $mod 'scene-host-status.tsv'),"error`tmissing replica mesh`n")
Update-CoopAutoReports $state 0 $capture
Assert-Auto ($state.Captures -eq 1 -and $state.CaptureReason -like 'component_error*') 'Component error without controller error missed'
Remove-Item -LiteralPath (Join-Path $mod 'scene-host-status.tsv')
$state=New-State
Remove-Item -LiteralPath (Join-Path $mod 'diagnostics-summary.json'),(Join-Path $mod 'shared-session-status.tsv')
Update-CoopAutoReports $state 90000 $capture
Assert-Auto ($state.CaptureReason -eq 'diagnostics_not_ready') 'Missing startup diagnostics not reported'
$state=New-State;Summary 1;Native 1;Update-CoopAutoReports $state 0 $capture
Summary 2;Native 2;Update-CoopAutoReports $state 30000 $capture
Assert-Auto ($state.Captures -eq 1 -and $state.CaptureReason -eq 'periodic_checkpoint') 'Initial checkpoint missing'
foreach($time in @(150000,270000,390000)){Summary $time;Native $time;Update-CoopAutoReports $state $time $capture}
Assert-Auto ($state.Captures -eq 4 -and $state.CheckpointSlot -eq 2) 'Checkpoint ring failed'
$names=@($script:captures|Where-Object {$_.reason -eq 'periodic_checkpoint'}|ForEach-Object {$_.file}|Select-Object -Unique)
Assert-Auto ($names.Count -eq 2) 'Checkpoint ring generated unbounded names'
$state=New-State;Summary 1;Native 1;Update-CoopAutoReports $state 0 $capture
Summary 2 'io incident';Native 2
$failing={param($s,$f,$r)throw 'disk failure'}
Update-CoopAutoReports $state 1000 $failing
Assert-Auto ($state.Errors -eq 1 -and $state.LastError -eq 'disk failure') 'Collection failure escaped observer'
Update-CoopAutoReports $state 2000 $failing
Assert-Auto ($state.Errors -eq 1) 'Failed collector entered retry loop'
Summary 3;Native 3;Update-CoopAutoReports $state 31000 $capture
Assert-Auto ($state.Captures -eq 1) 'Observer did not retry collection'
$before=$state.Captures;Update-CoopAutoReports $state 1000 $capture
Assert-Auto ($state.Captures -eq $before) 'Regressed clock triggered collection'
# Real collector path, including atomic replacement and retention of two files.
$state=New-State;Summary 1;Native 1;Update-CoopAutoReports $state 0
foreach($time in @(30000,150000,270000)){Summary $time;Native $time;Update-CoopAutoReports $state $time}
Assert-Auto ($state.Captures -eq 3 -and $state.Errors -eq 0) 'Real automatic ZIP collection failed'
foreach($time in @(400000,415000,430000)){Summary $time ('failure-'+$time) 6;Native $time;Update-CoopAutoReports $state $time}
Assert-Auto ($state.Captures -eq 6 -and $state.Errors -eq 0) 'Real incident collection failed'
$archives=@(Get-ChildItem -LiteralPath (Join-Path $root 'reports') -File -Filter '*-auto-checkpoint-*.zip')
Assert-Auto ($archives.Count -eq 2) 'Real automatic ZIP retention failed'
Assert-Auto (@(Get-ChildItem -LiteralPath (Join-Path $root 'reports') -File -Filter '*-auto-incident-*.zip').Count -eq 2) 'Incident retention failed'
Assert-Auto (@(Get-ChildItem -LiteralPath (Join-Path $root 'reports') -File -Filter '*.zip').Count -eq 4) 'Total auto ZIP retention exceeded'
Assert-Auto (@(Get-ChildItem -LiteralPath (Join-Path $root 'reports') -File -Filter '*.partial-*').Count -eq 0) 'Partial archive was published'
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach($archive in $archives){$zip=[IO.Compression.ZipFile]::OpenRead($archive.FullName);try{Assert-Auto ($null -ne $zip.GetEntry('auto-reports.json')) 'Automatic report reason missing'}finally{$zip.Dispose()}}
$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Auto-Reports.ps1'),[ref]$tokens,[ref]$errors)|Out-Null
Assert-Auto ($errors.Count -eq 0) 'Observer parse error'
Write-Output ("PASS: $script:checks automatic-report checks; virtual time; no game started. Fixture: $root")
