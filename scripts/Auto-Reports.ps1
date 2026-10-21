# Launcher-only observer. No game handles, input, UObject calls or network actions.
function New-CoopAutoReportState {
 param([string]$Root,[string]$Session,[string]$UserSaved,[string]$FallbackSaved,[long]$NowMs)
 $rootPath=(Resolve-Path -LiteralPath $Root).Path
 $sessionPath=(Resolve-Path -LiteralPath $Session).Path
 $evidence=[IO.Path]::GetFullPath((Join-Path $rootPath 'evidence'))+[IO.Path]::DirectorySeparatorChar
 if(!$sessionPath.StartsWith($evidence,[StringComparison]::OrdinalIgnoreCase)){throw 'Automatic reports require this profile evidence directory.'}
 $record=Get-Content -LiteralPath (Join-Path $sessionPath 'session.json') -Raw|ConvertFrom-Json
 if($record.role -notin @('host','guest')){throw 'Unknown automatic report role.'}
 $name=Split-Path $sessionPath -Leaf
 if($name -notmatch '^[A-Za-z0-9_.-]+$'){throw 'Invalid automatic report session name.'}
 return @{
  Root=$rootPath;Session=$sessionPath;Output=(Join-Path $sessionPath 'mod');UserSaved=$UserSaved;FallbackSaved=$FallbackSaved
  Name=$name;Role=$record.role;Started=$NowMs;LastNow=$NowMs;NextCheckpoint=($NowMs+30000)
  LuaMarker='';NativeMarker='';LuaSeen=$false;NativeSeen=$false;LuaAt=$NowMs;NativeAt=$NowMs;Summary=$null;Native=$null
  LastIssue='';PendingIssue='';LastIncident=-15000L;LastAttempt=-30000L;CheckpointSlot=0;IncidentSlot=0
  Captures=0;Errors=0;LastError=$null;LastReport=$null;CaptureReason=$null;NextRetry=0L
 }
}
function Read-CoopAutoReportFile {
 param([string]$Path,[switch]$Json)
 try{
  $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
  try{
   if($stream.Length -gt 32768){return $null}
   $buffer=New-Object byte[] 32769;$count=0
   while($count -lt $buffer.Length){$read=$stream.Read($buffer,$count,$buffer.Length-$count);if(!$read){break};$count+=$read}
   if($count -gt 32768){return $null}
   $text=[Text.Encoding]::UTF8.GetString($buffer,0,$count).TrimStart([char]0xfeff)
  }finally{$stream.Dispose()}
  if($Json){return $text|ConvertFrom-Json -ErrorAction Stop}
  $value=@{};foreach($line in $text -split "`n"){
   if($line -match '^([a-zA-Z0-9_]+)\t([^\r\n]*)\r?$'){$value[$matches[1]]=$matches[2]}
  }
  if($value.Count){return $value}
 }catch{}
 return $null
}
function Save-CoopAutoReportState {
 param($State,[long]$NowMs)
 $path=Join-Path $State.Session 'auto-reports.json';$temp=$path+'.tmp'
 try{
  [ordered]@{format='ac8-auto-reports-v1';utc=[DateTime]::UtcNow.ToString('o');role=$State.Role;elapsed_ms=($NowMs-$State.Started);captures=$State.Captures;errors=$State.Errors;last_error=$State.LastError;last_reason=$State.CaptureReason;last_report=$State.LastReport;pending_issue=$State.PendingIssue;checkpoint_slots=2;incident_slots=2;checkpoint_interval_ms=120000;stale_observation_ms=10000;automatic_report_budget_bytes=67108864}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $temp -Encoding UTF8
  Move-Item -LiteralPath $temp -Destination $path -Force
 }catch{}
}
function Update-CoopAutoReports {
 param($State,[long]$NowMs,[scriptblock]$Capture)
 # A monotonic clock is supplied by the launcher; tests inject virtual time.
 if($NowMs -lt $State.LastNow){return};$State.LastNow=$NowMs
 $summary=Read-CoopAutoReportFile -Path (Join-Path $State.Output 'diagnostics-summary.json') -Json
 if($summary -and $summary.format -eq 'ac8-diagnostic-summary-v1'){
  $marker=[string]$summary.sequence+'|'+[string]$summary.updated_unix
  if(!$State.LuaSeen -or $marker -ne $State.LuaMarker){$State.LuaAt=$NowMs;$State.LuaMarker=$marker;$State.LuaSeen=$true}
  $State.Summary=$summary
 }
 $native=Read-CoopAutoReportFile -Path (Join-Path $State.Output 'shared-session-status.tsv')
 if($native -and $native.format -eq 'ac8-session-status-v3' -and $native.heartbeat){
  $marker=[string]$native.config_token+'|'+[string]$native.heartbeat
  if(!$State.NativeSeen -or $marker -ne $State.NativeMarker){$State.NativeAt=$NowMs;$State.NativeMarker=$marker;$State.NativeSeen=$true}
  $State.Native=$native
 }
 $last=if($State.Summary){$State.Summary.last_state}else{$null}
 $issue=''
 if($last -and ($last.error -or $last.local_failure)){
  $message=if($last.local_failure){[string]$last.local_failure}else{[string]$last.error}
  $issue='reported_error|'+[string]$last.generation+'|'+$message.Substring(0,[Math]::Min(512,$message.Length))
 }elseif($last -and [string]$last.phase -eq '8'){
  $issue='session_stopped|'+[string]$last.generation+'|'+[string]$last.stop_reason
 }elseif($native -and [string]$native.phase -eq '8'){
  $issue='native_stopped|'+[string]$native.config_token+'|'+[string]$native.generation+'|'+[string]$native.stop_reason
 }elseif($State.LuaSeen -and $NowMs-$State.LuaAt -ge 10000){
  $issue='lua_observation_stalled'
 }elseif(!$State.LuaSeen -and $NowMs-$State.Started -ge 90000){
  $issue='diagnostics_not_ready'
 }elseif($last -and $last.active -and (($State.NativeSeen -and $NowMs-$State.NativeAt -ge 10000) -or (!$State.NativeSeen -and $NowMs-$State.Started -ge 90000))){
  $issue='native_observation_stalled'
 }
 if(!$issue){
  foreach($file in @('scene-host-status.tsv','cinema-playback-status.tsv','guest-pilot-status.tsv')){
   $part=Read-CoopAutoReportFile -Path (Join-Path $State.Output $file)
   if($part -and ($part.error -or $part.visual_error)){
    $message=if($part.error){[string]$part.error}else{[string]$part.visual_error}
    $issue='component_error|'+$file+'|'+$message.Substring(0,[Math]::Min(512,$message.Length));break
   }
  }
 }
 if($issue -and $State.LuaSeen -and $NowMs-$State.LuaAt -ge 10000 -and $issue -ne 'lua_observation_stalled'){$issue+='|lua_observation_stalled'}
 # A long pause/minimized window can also stop observations. This is a signal,
 # never proof of a freeze and never grounds for killing or restarting the game.
 if($issue -ne $State.LastIssue){$State.LastIssue=$issue;if($issue){$State.PendingIssue=$issue}}
 $incident=$State.PendingIssue -and $NowMs-$State.LastIncident -ge 15000
 $checkpoint=$NowMs -ge $State.NextCheckpoint
 if($NowMs -lt $State.NextRetry -or !($incident -or $checkpoint)){return}
 $kind=if($incident){'incident'}else{'checkpoint'}
 $reason=if($incident){$State.PendingIssue}else{'periodic_checkpoint'}
 $slot=if($incident){($State.IncidentSlot%2)+1}else{($State.CheckpointSlot%2)+1}
 $file=$State.Name+'-auto-'+$kind+'-'+$slot.ToString('D2')+'.zip'
 $State.CaptureReason=$reason;$State.LastAttempt=$NowMs;Save-CoopAutoReportState -State $State -NowMs $NowMs
 try{
  if($Capture){$report=& $Capture $State $file $reason}
  else{
   try{Copy-CoopDiagnosticLogs -UserSaved $State.UserSaved -Output $State.Output -Since ([DateTime]::Parse((Get-Content -LiteralPath (Join-Path $State.Session 'session.json') -Raw|ConvertFrom-Json).started)) -RuntimeLog (Join-Path $State.Root 'runtime/UE4SS.log') -FallbackSaved $State.FallbackSaved}catch{}
   $report=& (Join-Path $State.Root 'Collect-CoopLogs.ps1') -SessionDirectory $State.Session -ReportsDirectory (Join-Path $State.Root 'reports') -FileName $file -MaxTotalBytes 67108864 -MaxFileBytes 16777216 -CompressionLevel Fastest
  }
  if(!$report){throw 'Automatic collector returned no archive.'}
  $State.Captures++;$State.LastReport=[string]$report;$State.LastError=$null;$State.NextRetry=0L
  if($incident){$State.IncidentSlot=$slot;$State.LastIncident=$NowMs;$State.PendingIssue=''}else{$State.CheckpointSlot=$slot}
  $State.NextCheckpoint=$NowMs+120000
 }catch{
  $State.Errors++;$State.LastError=$_.Exception.Message;$State.NextRetry=$NowMs+30000
 }
 Save-CoopAutoReportState -State $State -NowMs $NowMs
}
