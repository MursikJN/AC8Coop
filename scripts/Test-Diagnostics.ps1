# Offline fixtures only: report archive, live files and crash metadata policy.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Session-Diagnostics.ps1')
$scratch=Join-Path $repo ('build/diagnostic-ps-test-'+[Guid]::NewGuid().ToString('N'))
$session=Join-Path $scratch 'evidence/session-fixture';$mod=Join-Path $session 'mod';$reports=Join-Path $scratch 'reports'
$saved=Join-Path $session 'guest-userdata/Saved'
foreach($dir in @($mod,(Join-Path $saved 'SaveGames'),(Join-Path $saved 'Logs'),(Join-Path $saved 'Crashes/one'))){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
$script:checks=0
function Assert-Diagnostic([bool]$Condition,[string]$Message){$script:checks++;if(!$Condition){throw $Message}}
$record=[ordered]@{role='guest';revision='r29-debug1-development';started=(Get-Date).AddMinutes(-1).ToString('o');session_id='fixture';exit_code=0}
$record|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding UTF8
[IO.File]::WriteAllText((Join-Path $mod 'diagnostics-01.jsonl'),"{`"event`":`"fixture`"}`n")
[IO.File]::WriteAllText((Join-Path $mod 'scene-client.ac8w'),'AC8W-fixture')
[IO.File]::WriteAllText((Join-Path $mod 'guest-pilot-status.tsv'),"active`t1`n")
[IO.File]::WriteAllText((Join-Path $saved 'SaveGames/private.json'),'DO NOT EXPORT')
[IO.File]::WriteAllText((Join-Path $saved 'SaveGames/private.sav'),'DO NOT EXPORT')
[IO.File]::WriteAllText((Join-Path $saved 'Logs/current.log'),'current game log')
[IO.File]::WriteAllText((Join-Path $saved 'Logs/old.log'),'old game log');(Get-Item -LiteralPath (Join-Path $saved 'Logs/old.log')).LastWriteTime=(Get-Date).AddDays(-1)
[IO.File]::WriteAllText((Join-Path $saved 'Crashes/one/CrashContext.runtime-xml'),'<stack/>')
[IO.File]::WriteAllText((Join-Path $saved 'Crashes/one/memory.dmp'),'DO NOT EXPORT MEMORY')
[IO.File]::WriteAllText((Join-Path $scratch 'UE4SS.log'),'ue4ss')
$fallback=Join-Path $scratch 'fallback/Saved';New-Item -ItemType Directory -Path (Join-Path $fallback 'Logs') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $fallback 'Logs/fallback.log'),'fallback log if the game ignored UserDir')
Copy-CoopDiagnosticLogs -UserSaved $saved -Output $mod -Since ([DateTime]::Parse($record.started)) -RuntimeLog (Join-Path $scratch 'UE4SS.log') -FallbackSaved $fallback
$copied=Get-ChildItem -LiteralPath (Join-Path $mod 'game-evidence') -File
Assert-Diagnostic ($copied.Count -eq 4) 'Wrong logs copied'
Assert-Diagnostic (!($copied.Name -match 'old|\.dmp$')) 'Old logs or memory dumps copied'
$live=Join-Path $mod 'live.log';$writer=[IO.File]::Open($live,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
try{
 $bytes=[Text.Encoding]::UTF8.GetBytes('live snapshot');$writer.Write($bytes,0,$bytes.Length);$writer.Flush()
 $archive=& (Join-Path $repo 'coop/Collect-CoopLogs.ps1') -SessionDirectory $session -ReportsDirectory $reports
}finally{$writer.Dispose()}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try{
 $names=@($zip.Entries|ForEach-Object {$_.FullName})
 Assert-Diagnostic ($names -contains 'mod/diagnostics-01.jsonl') 'Structured trace omitted'
 Assert-Diagnostic ($names -contains 'mod/scene-client.ac8w') 'Scene snapshot omitted'
 Assert-Diagnostic ($names -contains 'mod/live.log') 'Live-open log omitted'
 Assert-Diagnostic (!($names -match 'guest-userdata|private|\.dmp$')) 'Save or memory exported'
 $entry=$zip.GetEntry('report-manifest.json');$reader=[IO.StreamReader]::new($entry.Open());try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
 Assert-Diagnostic ($manifest.live_snapshot -eq $true) 'Live snapshot incorrectly marked final'
 Assert-Diagnostic ($manifest.role -eq 'guest') 'Role missing'
 foreach($file in $manifest.files){
  $entry=$zip.GetEntry($file.path);$hash=[Security.Cryptography.SHA256]::Create();$input=$entry.Open()
  try{$actual=[BitConverter]::ToString($hash.ComputeHash($input)).Replace('-','')}finally{$input.Dispose();$hash.Dispose()}
  Assert-Diagnostic ($actual -eq $file.sha256) ('Report hash mismatch: '+$file.path)
 }
}finally{$zip.Dispose()}
$record.finished=(Get-Date).ToString('o');$record|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding UTF8
$final=& (Join-Path $repo 'coop/Collect-CoopLogs.ps1') -SessionDirectory $session -ReportsDirectory $reports
$zip=[IO.Compression.ZipFile]::OpenRead($final)
try{$reader=[IO.StreamReader]::new($zip.GetEntry('report-manifest.json').Open());try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()};Assert-Diagnostic (!$manifest.live_snapshot) 'Final snapshot marked live'}finally{$zip.Dispose()}
foreach($file in @('Start-SteamLobby.ps1','Session-Diagnostics.ps1')){
 $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)|Out-Null
 Assert-Diagnostic ($errors.Count -eq 0) ('PowerShell parse errors: '+$file)
}
$invalidProfile=Join-Path $scratch 'invalid-profile';New-Item -ItemType Directory -Path $invalidProfile -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-SteamLobby.ps1') -Destination $invalidProfile
[ordered]@{revision='r29-debug1-development';session_diagnostics=$true;files=@()}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $invalidProfile 'lobby-manifest.json') -Encoding UTF8
# The fixture contains no EXE. It must fail before any game/process validation.
$psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $invalidProfile 'Start-SteamLobby.ps1')+'" -GameDirectory "'+$invalidProfile+'" -ValidateOnly'
$child=[Diagnostics.Process]::Start($psi);$stdout=$child.StandardOutput.ReadToEnd();$stderr=$child.StandardError.ReadToEnd();$child.WaitForExit()
Assert-Diagnostic ($child.ExitCode -ne 0) 'Missing game was accepted'
$failure=@(Get-ChildItem -LiteralPath (Join-Path $invalidProfile 'reports') -Filter 'launch-failure-*.json' -File)
Assert-Diagnostic ($failure.Count -eq 1) 'Launch failure was not recorded'
$failureRecord=Get-Content -LiteralPath $failure[0].FullName -Raw|ConvertFrom-Json
Assert-Diagnostic ($failureRecord.error -match 'AceCombat8.exe') 'Launch failure lost actual error text'
Write-Output ("PASS: $script:checks diagnostic PowerShell checks; no game started. Fixture: $scratch")
