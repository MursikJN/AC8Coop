[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SessionDirectory,
 [Parameter(Mandatory=$true)][string]$ReportsDirectory,
 [ValidatePattern('^$|^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$')][string]$FileName='',
 [ValidateRange(1048576,268435456)][long]$MaxTotalBytes=268435456,
 [ValidateRange(1048576,67108864)][long]$MaxFileBytes=67108864,
 [ValidateSet('Optimal','Fastest')][string]$CompressionLevel='Optimal'
)
$ErrorActionPreference='Stop'
$session=(Resolve-Path -LiteralPath $SessionDirectory).Path
if (!(Test-Path -LiteralPath (Join-Path $session 'session.json'))) { throw 'Not a recorded game session.' }
$reports=[IO.Path]::GetFullPath($ReportsDirectory)
New-Item -ItemType Directory -Path $reports -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
$report=if($FileName){Join-Path $reports $FileName}else{Join-Path $reports ((Split-Path $session -Leaf)+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'.zip')}
$report=[IO.Path]::GetFullPath($report)
$prefix=$reports.TrimEnd([char[]]@('\','/'))+[IO.Path]::DirectorySeparatorChar
if(!$report.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Report is outside ReportsDirectory.'}
$temporary=$report+'.partial-'+[Guid]::NewGuid().ToString('N')
$compression=[IO.Compression.CompressionLevel]::$CompressionLevel
$record=Get-Content -LiteralPath (Join-Path $session 'session.json') -Raw|ConvertFrom-Json
$manifest=[ordered]@{format='ac8-coop-debug-report-v2';created=[DateTime]::UtcNow.ToString('o');source_session=(Split-Path $session -Leaf);role=$record.role;revision=$record.revision;live_snapshot=![bool]$record.finished;files=@();skipped=@()}
$stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
$bytes=0L;$complete=$false
try {
    # Traverse explicit evidence trees only. Never descend into saved profiles or links.
    $queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($session)
    $inventory=New-Object 'System.Collections.Generic.List[object]';$visited=0
    while($queue.Count -gt 0 -and $visited -lt 512 -and $inventory.Count -lt 4096){
        $folder=$queue.Dequeue();$visited++
        foreach($item in Get-ChildItem -LiteralPath $folder -Force){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($item.PSIsContainer){
                if($item.Name -in @('mod','host','guest','game-evidence','crash','crashes') -and $queue.Count -lt 512){$queue.Enqueue($item.FullName)}
            }elseif($inventory.Count -lt 4096){$inventory.Add($item)}
        }
    }
    if($queue.Count -or $inventory.Count -ge 4096){$manifest.skipped+=@{path='inventory';reason='directory/file budget'}}
    foreach ($file in $inventory) {
        $relative=$file.FullName.Substring($session.Length+1).Replace('\','/')
        if ($file.Extension.ToLowerInvariant() -notin @('.json','.jsonl','.tsv','.txt','.log','.lua','.xml','.runtime-xml','.ac8w','.ac8p')) { continue }
        if ($file.Name -like '*.tmp' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        if ($file.Length -gt $MaxFileBytes -or $bytes+$file.Length -gt $MaxTotalBytes) { $manifest.skipped+=@{path=$relative;reason='report size limit'};continue }
        $inputStream=$null
        try {
            $inputStream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            $memory=[IO.MemoryStream]::new()
            try {
                # Bound reads even if a live logger keeps appending.
                $remaining=[Math]::Min($inputStream.Length,[Math]::Min($MaxFileBytes,$MaxTotalBytes-$bytes));$buffer=New-Object byte[] 65536
                while ($remaining -gt 0) { $read=$inputStream.Read($buffer,0,[int][Math]::Min($remaining,$buffer.Length));if (!$read) { break };$memory.Write($buffer,0,$read);$remaining-=$read }
                $data=$memory.ToArray()
            } finally { $memory.Dispose() }
            $entry=$zip.CreateEntry($relative,$compression);$entryStream=$entry.Open()
            try { $entryStream.Write($data,0,$data.Length) } finally { $entryStream.Dispose() }
            $hasher=[Security.Cryptography.SHA256]::Create()
            try { $hash=[BitConverter]::ToString($hasher.ComputeHash($data)).Replace('-','') } finally { $hasher.Dispose() }
            $manifest.files+=@{path=$relative;bytes=$data.Length;sha256=$hash};$bytes+=$data.Length
        } catch { $manifest.skipped+=@{path=$relative;reason=$_.Exception.Message} }
        finally { if ($null -ne $inputStream) { $inputStream.Dispose() } }
    }
    $entry=$zip.CreateEntry('report-manifest.json');$entryStream=$entry.Open()
    try { $data=[Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 6));$entryStream.Write($data,0,$data.Length) } finally { $entryStream.Dispose() }
    $complete=$true
} finally { $zip.Dispose();$stream.Dispose();if(!$complete -and (Test-Path -LiteralPath $temporary)){Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue} }
try{Move-Item -LiteralPath $temporary -Destination $report -Force}catch{Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue;throw}
[ordered]@{archive=$report;created=$manifest.created;files=$manifest.files.Count;skipped=$manifest.skipped.Count} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'latest-debug-report.json') -Encoding UTF8
Write-Output $report
