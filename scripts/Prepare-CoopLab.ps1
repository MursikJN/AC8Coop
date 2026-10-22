[CmdletBinding()]
param([string]$SourceGameDirectory,[switch]$ValidateOnly,[switch]$PlanOnly,[ValidateSet('Compact','Full')][string]$StorageMode='Compact')
$ErrorActionPreference='Stop';$root=$PSScriptRoot
. (Join-Path $root 'Coop-Kit.ps1')
try{
 $m=Test-CoopKit $root
 if($ValidateOnly){[ordered]@{revision=$m.revision;kit_update=$m.kit_update;kit_verified=$true;game_started=$false;lab_prepared=(Test-Path -LiteralPath (Join-Path $root 'lab-game/.ac8-coop-lab.json'));default_storage='compact'}|ConvertTo-Json;return}
 if(Test-Path -LiteralPath (Join-Path $root 'lab-game/.ac8-coop-lab.json')){Test-CoopLab -Root $root -Manifest $m|Out-Null;Write-Output 'Laboratory copy already verified.';return}
 if(!$SourceGameDirectory){Add-Type -AssemblyName System.Windows.Forms;$dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Select the original ACE COMBAT 8 folder (containing Game and Engine). It will only be read.';if($dialog.ShowDialog() -ne 'OK'){throw 'Preparation cancelled'};$SourceGameDirectory=$dialog.SelectedPath}
 $source=(Resolve-Path -LiteralPath $SourceGameDirectory).Path.TrimEnd([char[]]@('\','/'))
 if(Test-Path -LiteralPath (Join-Path $source 'AceCombat8.exe')){$source=[IO.Path]::GetFullPath((Join-Path $source '../../..')).TrimEnd([char[]]@('\','/'))}
 $lab=[IO.Path]::GetFullPath((Join-Path $root 'lab-game'))
 if($lab -eq $source -or $lab.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($lab+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Lab and original must be separate trees'}
 Assert-CoopPlainPath $source;Assert-CoopPlainPath $lab
 if(Test-Path -LiteralPath $lab){throw 'Incomplete/existing lab-game folder. Preserve it and choose a fresh kit directory; no files were overwritten.'}
 $game=Join-Path $source 'Game/Binaries/Win64/AceCombat8.exe';$steam=Join-Path $source 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll'
 if((Get-FileHash -LiteralPath $game).Hash -ne $m.game_sha256 -or (Get-FileHash -LiteralPath $steam).Hash -ne $m.steam_sha256){throw 'Source build mismatch; 25201480 required'}
 foreach($name in @('dwmapi.dll','dinput8.dll','dxgi.dll','winmm.dll','UE4SS.dll')){if(Test-Path -LiteralPath (Join-Path $source ('Game/Binaries/Win64/'+$name))){throw ('Source contains a loader; close its launcher or use a clean copy: '+$name)}}
 $inventory=New-Object 'System.Collections.Generic.List[object]';$archives=New-Object 'System.Collections.Generic.List[object]';$queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($source);$total=0L;$copied=0L;$shared=0L
 while($queue.Count){$dir=$queue.Dequeue();foreach($item in Get-ChildItem -LiteralPath $dir -Force){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Source contains linked content: '+$item.FullName)}
  if($item.PSIsContainer){$queue.Enqueue($item.FullName)}else{
   $relative=$item.FullName.Substring($source.Length+1).Replace('\','/');$share=$StorageMode -eq 'Compact' -and (Test-CoopArchiveRelative $relative)
   $inventory.Add([pscustomobject]@{file=$item;relative=$relative;share=$share});$total+=$item.Length
   if($share){$shared+=$item.Length;$archives.Add([pscustomobject]@{path=$relative;bytes=$item.Length;write_ticks=$item.LastWriteTimeUtc.Ticks})}else{$copied+=$item.Length}
  }
 }}
 if($StorageMode -eq 'Compact' -and (!$archives.Count -or $copied -gt 5GB)){throw ('Compact layout not supported for this source tree: copied bytes '+$copied+'. Choose a clean game root; no copy was started.')}
 $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($lab));$required=$copied+1GB
 if($PlanOnly){[ordered]@{storage_mode=$StorageMode.ToLowerInvariant();copy_bytes=$copied;shared_bytes=$shared;source_bytes=$total;required_free_bytes=$required;available_free_bytes=$drive.AvailableFreeSpace;archive_count=$archives.Count;game_started=$false;originals_written=$false}|ConvertTo-Json;return}
 if($drive.AvailableFreeSpace -lt $required){throw ('Insufficient disk space: '+$copied+' bytes to copy plus 1 GiB reserve. Compact mode avoids copying resource archives.')}
 # Probe link privileges before creating lab-game or copying gigabytes.
 if($StorageMode -eq 'Compact'){
  $probe=Join-Path $root ('.compact-link-probe-'+[Guid]::NewGuid().ToString('N'))
  try{New-CoopArchiveLink -Link $probe -Original (Join-Path $source $archives[0].path)}finally{if(Test-Path -LiteralPath $probe){[IO.File]::Delete($probe)}}
 }
 New-Item -ItemType Directory -Path $lab|Out-Null
 $marker=[ordered]@{format='ac8-isolated-lab-v2';state='copying';storage_mode=$StorageMode.ToLowerInvariant();source=$source;destination=$lab;game_sha256=$m.game_sha256;bytes=$total;copied_bytes=$copied;shared_bytes=$shared;archives=@($archives.ToArray());created_utc=[DateTime]::UtcNow.ToString('o');links_used=($StorageMode -eq 'Compact');directory_links_used=$false}
 $markerPath=Join-Path $lab '.ac8-coop-lab.json';$marker|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $markerPath -Encoding UTF8
 $i=0;foreach($entry in $inventory){
  $target=Join-Path $lab $entry.relative;New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent)|Out-Null
  if($entry.share){New-CoopArchiveLink -Link $target -Original $entry.file.FullName}else{Copy-Item -LiteralPath $entry.file.FullName -Destination $target}
  $i++;Write-Progress -Activity ('Preparing '+$StorageMode+' laboratory (original unchanged)') -Status $entry.relative -PercentComplete ([int](100*$i/[Math]::Max(1,$inventory.Count)))
 }
 if((Get-FileHash -LiteralPath (Join-Path $lab 'Game/Binaries/Win64/AceCombat8.exe')).Hash -ne $m.game_sha256 -or (Get-FileHash -LiteralPath (Join-Path $lab 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll')).Hash -ne $m.steam_sha256){throw 'Copy verification failed'}
 $marker.state='complete';$marker|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $markerPath -Encoding UTF8
 Test-CoopLab -Root $root -Manifest $m|Out-Null;Write-Progress -Activity 'Copying game into isolated laboratory (original is read-only)' -Completed
 Write-Output 'Lab ready. Original game unchanged. Launch Start-Host.cmd or Start-Guest.cmd.'
}catch{
 $reports=Join-Path $root 'reports';New-Item -ItemType Directory -Force -Path $reports|Out-Null
 [ordered]@{format='ac8-lab-preparation-failure-v1';error=$_.Exception.Message;game_started=$false;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $reports 'lab-preparation-failure.json') -Encoding UTF8
 throw
}
