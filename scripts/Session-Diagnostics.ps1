# Passive launcher evidence helpers. Dot-sourcing never starts a process.
function Get-CoopDiagnosticEnvironment {
    $info=[ordered]@{format='ac8-diagnostic-environment-v1';utc=[DateTime]::UtcNow.ToString('o');os_version=[Environment]::OSVersion.VersionString;process_64bit=[Environment]::Is64BitProcess;powershell=$PSVersionTable.PSVersion.ToString();query_errors=@()}
    try {$info.gpu=@(Get-CimInstance Win32_VideoController -OperationTimeoutSec 3 -ErrorAction Stop|Select-Object Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution)}catch{$info.query_errors+='gpu query unavailable'}
    try {$os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3 -ErrorAction Stop;$info.os_build=$os.BuildNumber;$info.ram_total_kb=$os.TotalVisibleMemorySize;$info.ram_free_kb=$os.FreePhysicalMemory}catch{$info.query_errors+='os memory query unavailable'}
    return $info
}
function Copy-CoopDiagnosticLogs {
    param([string]$UserSaved,[string]$Output,[DateTime]$Since,[string]$RuntimeLog,[string]$FallbackSaved)
    $notes=New-Object 'System.Collections.Generic.List[string]'
    # Copy only existing game logs and textual crash receipts from this run.
    $candidates=@()
    if($RuntimeLog -and (Test-Path -LiteralPath $RuntimeLog -PathType Leaf)){$runtimeFile=Get-Item -LiteralPath $RuntimeLog;if($runtimeFile.LastWriteTime -ge $Since){$candidates+=$runtimeFile}}
    $roots=@($UserSaved)
    if($FallbackSaved -and [IO.Path]::GetFullPath($FallbackSaved) -ne [IO.Path]::GetFullPath($UserSaved)){$roots+=$FallbackSaved}
    foreach($sourceSaved in $roots){foreach($folder in @('Logs','Crashes')){
        $base=Join-Path $sourceSaved $folder
        if(!(Test-Path -LiteralPath $base -PathType Container)){continue}
        $baseInfo=Get-Item -LiteralPath $base
        if($baseInfo.Attributes -band [IO.FileAttributes]::ReparsePoint){$notes.Add('Skipped linked '+$folder);continue}
        $queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($base)
        $visited=0
        while($queue.Count -gt 0 -and $visited -lt 64){
            $dir=$queue.Dequeue();$visited++
            foreach($entry in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue){
                if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
                if($entry.PSIsContainer){if($queue.Count -lt 64){$queue.Enqueue($entry.FullName)};continue}
                if($entry.LastWriteTime -lt $Since){continue}
                if($entry.Extension.ToLowerInvariant() -in @('.log','.txt','.xml','.runtime-xml')){$candidates+=$entry}
            }
        }
    }}
    $folder=Join-Path $Output 'game-evidence';New-Item -ItemType Directory -Force -Path $folder|Out-Null
    $total=0L;$count=0
    foreach($file in $candidates){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
        if($file.Length -gt 32MB -or $total+$file.Length -gt 64MB -or $count -ge 128){$notes.Add('Skipped oversized/budget file: '+$file.Name);continue}
        $count++;$target=Join-Path $folder ($count.ToString('D3')+'-'+$file.Name)
        try{Copy-Item -LiteralPath $file.FullName -Destination $target -ErrorAction Stop;$total+=$file.Length}catch{$notes.Add('Could not copy '+$file.Name)}
    }
    [ordered]@{format='ac8-game-evidence-v1';copied=$count;bytes=$total;notes=$notes.ToArray();automatic_memory_dumps=$false}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $Output 'game-evidence-index.json') -Encoding UTF8
}
