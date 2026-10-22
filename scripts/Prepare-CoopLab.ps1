[CmdletBinding()]
param([string]$SourceGameDirectory,[switch]$ValidateOnly)
$ErrorActionPreference='Stop';$root=$PSScriptRoot
. (Join-Path $root 'Coop-Kit.ps1')
try{
 $m=Test-CoopKit $root
 if($ValidateOnly){[ordered]@{revision=$m.revision;kit_verified=$true;game_started=$false;lab_prepared=(Test-Path -LiteralPath (Join-Path $root 'lab-game/.ac8-coop-lab.json'))}|ConvertTo-Json;return}
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
 $inventory=New-Object 'System.Collections.Generic.List[object]';$queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($source);$total=0L
 while($queue.Count){$dir=$queue.Dequeue();foreach($item in Get-ChildItem -LiteralPath $dir -Force){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Source contains linked content: '+$item.FullName)};if($item.PSIsContainer){$queue.Enqueue($item.FullName)}else{$inventory.Add($item);$total+=$item.Length}}}
 $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($lab));if($drive.AvailableFreeSpace -lt $total+1GB){throw ('Insufficient disk space for a full independent copy: '+$total+' bytes required plus reserve')}
 New-Item -ItemType Directory -Path $lab|Out-Null
 $marker=[ordered]@{format='ac8-isolated-lab-v1';state='copying';source=$source;destination=$lab;game_sha256=$m.game_sha256;bytes=$total;created_utc=[DateTime]::UtcNow.ToString('o');links_used=$false}
 $markerPath=Join-Path $lab '.ac8-coop-lab.json';$marker|ConvertTo-Json|Set-Content -LiteralPath $markerPath -Encoding UTF8
 $i=0;foreach($file in $inventory){$relative=$file.FullName.Substring($source.Length+1);$target=Join-Path $lab $relative;New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent)|Out-Null;Copy-Item -LiteralPath $file.FullName -Destination $target;$i++;Write-Progress -Activity 'Copying game into isolated laboratory (original is read-only)' -Status $relative -PercentComplete ([int](100*$i/[Math]::Max(1,$inventory.Count)))}
 if((Get-FileHash -LiteralPath (Join-Path $lab 'Game/Binaries/Win64/AceCombat8.exe')).Hash -ne $m.game_sha256 -or (Get-FileHash -LiteralPath (Join-Path $lab 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll')).Hash -ne $m.steam_sha256){throw 'Copy verification failed'}
 $marker.state='complete';$marker|ConvertTo-Json|Set-Content -LiteralPath $markerPath -Encoding UTF8
 Test-CoopLab -Root $root -Manifest $m|Out-Null;Write-Progress -Activity 'Copying game into isolated laboratory (original is read-only)' -Completed
 Write-Output 'Lab ready. Original game unchanged. Launch Start-Host.cmd or Start-Guest.cmd.'
}catch{
 $reports=Join-Path $root 'reports';New-Item -ItemType Directory -Force -Path $reports|Out-Null
 [ordered]@{format='ac8-lab-preparation-failure-v1';error=$_.Exception.Message;game_started=$false;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $reports 'lab-preparation-failure.json') -Encoding UTF8
 throw
}
