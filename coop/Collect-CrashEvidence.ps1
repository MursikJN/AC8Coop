[CmdletBinding()]
param(
    [string]$SavedDirectory=(Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved'),
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports'),
    [switch]$IncludeWindowsEvents
)
$ErrorActionPreference='Stop'
$saved=[IO.Path]::GetFullPath($SavedDirectory)
if (!(Test-Path -LiteralPath $saved -PathType Container)) { throw "Game Saved folder not found: $saved" }
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$stage=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('AC8-crash-'+$stamp)
New-Item -ItemType Directory -Force -Path $stage|Out-Null
$notes=New-Object 'System.Collections.Generic.List[string]'
$manifest=New-Object 'System.Collections.Generic.List[object]'
function Copy-Evidence([IO.FileInfo]$File,[string]$Category) {
    if ($File.Attributes -band [IO.FileAttributes]::ReparsePoint) { $notes.Add('Skipped linked file: '+$File.Name);return }
    $limit=if($File.Extension -eq '.dmp'){268435456}else{20971520}
    if($File.Length -gt $limit){$notes.Add('Skipped large file: '+$File.Name+' bytes='+$File.Length);return}
    $folder=Join-Path $stage $Category;New-Item -ItemType Directory -Force -Path $folder|Out-Null
    $target=Join-Path $folder $File.Name;Copy-Item -LiteralPath $File.FullName -Destination $target
    $manifest.Add([ordered]@{category=$Category;name=$File.Name;bytes=$File.Length;last_write_utc=$File.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $target).Hash})
}
$crashRoot=Join-Path $saved 'Crashes';$latest=$null
if(Test-Path -LiteralPath $crashRoot) {
    $latest=Get-ChildItem -LiteralPath $crashRoot -Directory|Where-Object {!($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
}
if($latest) {
    $notes.Add('Crash folder: '+$latest.Name)
    Get-ChildItem -LiteralPath $latest.FullName -File|Where-Object {$_.Extension -in @('.runtime-xml','.xml','.dmp','.txt','.log','.ini')}|ForEach-Object {Copy-Evidence $_ 'engine-crash'}
} else {$notes.Add('No engine crash folder found.')}
$logs=Join-Path $saved 'Logs'
if(Test-Path -LiteralPath $logs) {
    Get-ChildItem -LiteralPath $logs -File -Filter '*.log'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1|ForEach-Object {Copy-Evidence $_ 'engine-log'}
}
if($IncludeWindowsEvents) {
    try {
        $eventEnd=Get-Date;$eventStart=$eventEnd.AddHours(-3)
        if($latest){$eventStart=$latest.LastWriteTime.AddMinutes(-10);$eventEnd=$latest.LastWriteTime.AddMinutes(10)}
        $events=Get-WinEvent -FilterHashtable @{LogName='Application';Id=@(1000,1001);StartTime=$eventStart;EndTime=$eventEnd} -MaxEvents 200 -ErrorAction Stop|Where-Object {$_.Message -match '(?i)AceCombat8\.exe'}
        if($events){$events|Select-Object TimeCreated,Id,ProviderName,Message|Format-List|Out-String -Width 240|Set-Content -LiteralPath (Join-Path $stage 'game-windows-events.txt') -Encoding UTF8}
        else {$notes.Add('No matching game Windows error events.')}
    }catch{$notes.Add('Windows event read: '+$_.Exception.Message)}
}
$notes|Set-Content -LiteralPath (Join-Path $stage 'collection-notes.txt') -Encoding UTF8
ConvertTo-Json -InputObject $manifest.ToArray() -Depth 5|Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8
$archive=$stage+'.zip';Compress-Archive -LiteralPath $stage -DestinationPath $archive
Write-Output "Crash report created: $archive"
Write-Output 'Game was not launched. No game files, settings or saves were changed.'
