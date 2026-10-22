# Upgrade only a verified compact-1 file-link tree; no game process is started.
function Repair-CoopCompactLab {
 param([string]$Root,$Manifest)
 if(Get-Process AceCombat8,start_protected_game -ErrorAction SilentlyContinue){throw 'Close the game normally before repairing the laboratory'}
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\','/'));Assert-CoopPlainPath $rootPath
 $lab=Join-Path $rootPath 'lab-game';Assert-CoopPlainPath $lab
 $markerPath=Join-Path $lab '.ac8-coop-lab.json';Assert-CoopPlainPath $markerPath
 $oldText=[IO.File]::ReadAllText($markerPath);$marker=$oldText|ConvertFrom-Json
 if($marker.format -eq 'ac8-isolated-lab-v3'){Test-CoopLab -Root $Root -Manifest $Manifest|Out-Null;Write-Output 'Compact laboratory already repaired and verified.';return}
 if($marker.format -ne 'ac8-isolated-lab-v2' -or $marker.state -ne 'complete' -or $marker.storage_mode -ne 'compact' -or [IO.Path]::GetFullPath($marker.destination) -ne $lab -or $marker.game_sha256 -ne $Manifest.game_sha256){throw 'Only a complete compact-1 laboratory can be repaired'}
 $source=[IO.Path]::GetFullPath($marker.source).TrimEnd([char[]]@('\','/'));Assert-CoopPlainPath $source
 if($source -eq $lab -or $source.StartsWith($lab+'\',[StringComparison]::OrdinalIgnoreCase) -or $lab.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source and lab trees overlap'}
 Initialize-CoopStorageNative
 $allowed=@{};foreach($entry in $marker.archives){if(!(Test-CoopArchiveRelative $entry.path) -or $allowed.ContainsKey($entry.path)){throw 'Invalid legacy archive list'};$allowed[$entry.path]=$entry}
 $queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($lab);$found=0
 while($queue.Count){foreach($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force){
  $relative=$item.FullName.Substring($lab.Length+1).Replace('\','/')
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
   if($item.PSIsContainer -or $item.LinkType -ne 'SymbolicLink' -or !$allowed.ContainsKey($relative)){throw 'Unexpected legacy link; no repair attempted'};$found++
  }elseif($item.PSIsContainer){$queue.Enqueue($item.FullName)}elseif($allowed.ContainsKey($relative)){throw 'Legacy archive is not a file symlink'}else{
   $f=[IO.File]::Open($item.FullName,'Open','Read','ReadWrite');try{if([Ac8CompactFiles]::LinkCount($f) -ne 1){throw 'Legacy copied file is a hardlink'}}finally{$f.Dispose()}
  }
 }}
 if(!$found -or $found -ne $allowed.Count){throw 'Missing legacy archive links'}
 Assert-CoopArchiveInventory -Paks (Join-Path $lab 'Game/Content/Paks') -Marker $marker
 foreach($relative in @('Game/Binaries/Win64/AceCombat8.exe','Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll')){
  $copy=Join-Path $lab $relative;$original=Join-Path $source $relative
  Assert-CoopSeparateBinary -Copy $copy -Original $original
  $expected=if($relative -like '*.exe'){$Manifest.game_sha256}else{$Manifest.steam_sha256}
  if((Get-FileHash -LiteralPath $copy).Hash -ne $expected -or (Get-FileHash -LiteralPath $original).Hash -ne $expected){throw 'Repair source/copied build mismatch'}
 }
 $streams=New-Object 'System.Collections.Generic.List[System.IO.FileStream]'
 $paks=Join-Path $lab 'Game/Content/Paks';Assert-CoopPlainPath $paks
 $backup=Join-Path $rootPath ('compact1-links-backup-'+[Guid]::NewGuid().ToString('N'))
 # Verify both absolute move targets are inside this kit, outside the source tree.
 foreach($path in @($paks,$backup)){if(!$path.StartsWith($rootPath+'\',[StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe repair move target'}}
 $moved=$false;$linked=$false;$complete=$false
 try{
  foreach($entry in $marker.archives){
   $original=Join-Path $source $entry.path;Assert-CoopPlainPath $original
   $a=[IO.File]::Open($original,'Open','Read','Read');$streams.Add($a)
   $b=[IO.File]::Open((Join-Path $lab $entry.path),'Open','Read','Read');$streams.Add($b)
   if([Ac8CompactFiles]::Identity($a) -ne [Ac8CompactFiles]::Identity($b) -or ![string]::Equals([Ac8CompactFiles]::FinalPath($b),$original,[StringComparison]::OrdinalIgnoreCase)){throw 'Legacy archive target mismatch'}
   if($a.Length -ne [long]$entry.bytes -or (Get-Item -LiteralPath $original).LastWriteTimeUtc.Ticks -ne [long]$entry.write_ticks){throw 'Legacy source changed; prepare a fresh kit'}
  }
  # Links are preserved for recovery, never recursively removed or followed.
  [IO.Directory]::Move($paks,$backup);$moved=$true
  New-CoopPaksJunction -Link $paks -Original (Join-Path $source 'Game/Content/Paks');$linked=$true
  $marker.format='ac8-isolated-lab-v3';$marker.directory_links_used=$true
  $marker|Add-Member -NotePropertyName archive_layout -NotePropertyValue 'paks-junction-v1' -Force
  $marker|Add-Member -NotePropertyName repaired_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
  $marker|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $markerPath -Encoding UTF8
  Test-CoopLab -Root $Root -Manifest $Manifest|Out-Null
  [IO.File]::WriteAllText((Join-Path $backup '.old-marker.json'),$oldText)
  $complete=$true
 }finally{
  foreach($stream in $streams){$stream.Dispose()}
  if(!$complete -and $moved){
   if($linked){$item=Get-Item -LiteralPath $paks -Force;if($item.LinkType -ne 'Junction'){throw 'Unexpected repair target; rollback stopped'};[IO.Directory]::Delete($paks)}
   if(!(Test-Path -LiteralPath $paks)){[IO.Directory]::Move($backup,$paks);[IO.File]::WriteAllText($markerPath,$oldText)}
  }
 }
 Write-Output 'Compact laboratory repaired: real Win32 archive sizes verified; game not started. Existing copied files and userdata preserved.'
}
