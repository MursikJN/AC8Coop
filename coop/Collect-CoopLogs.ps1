[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SessionDirectory,[Parameter(Mandatory=$true)][string]$ReportsDirectory)
$ErrorActionPreference='Stop'
$session=(Resolve-Path -LiteralPath $SessionDirectory).Path
if (!(Test-Path -LiteralPath (Join-Path $session 'session.json'))) { throw 'Not a recorded game session.' }
$reports=[IO.Path]::GetFullPath($ReportsDirectory)
New-Item -ItemType Directory -Path $reports -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
$report=Join-Path $reports ((Split-Path $session -Leaf)+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'.zip')
$record=Get-Content -LiteralPath (Join-Path $session 'session.json') -Raw|ConvertFrom-Json
$manifest=[ordered]@{format='ac8-coop-debug-report-v2';created=[DateTime]::UtcNow.ToString('o');source_session=(Split-Path $session -Leaf);role=$record.role;revision=$record.revision;live_snapshot=![bool]$record.finished;files=@();skipped=@()}
$stream=[IO.File]::Open($report,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
$bytes=0L
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
        if ($file.Length -gt 64MB -or $bytes+$file.Length -gt 256MB) { $manifest.skipped+=@{path=$relative;reason='report size limit'};continue }
        $inputStream=$null
        try {
            $inputStream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            $memory=[IO.MemoryStream]::new()
            try {
                # Bound reads even if a live logger keeps appending.
                $remaining=[Math]::Min($inputStream.Length,64MB);$buffer=New-Object byte[] 65536
                while ($remaining -gt 0) { $read=$inputStream.Read($buffer,0,[int][Math]::Min($remaining,$buffer.Length));if (!$read) { break };$memory.Write($buffer,0,$read);$remaining-=$read }
                $data=$memory.ToArray()
            } finally { $memory.Dispose() }
            $entry=$zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open()
            try { $entryStream.Write($data,0,$data.Length) } finally { $entryStream.Dispose() }
            $hasher=[Security.Cryptography.SHA256]::Create()
            try { $hash=[BitConverter]::ToString($hasher.ComputeHash($data)).Replace('-','') } finally { $hasher.Dispose() }
            $manifest.files+=@{path=$relative;bytes=$data.Length;sha256=$hash};$bytes+=$data.Length
        } catch { $manifest.skipped+=@{path=$relative;reason=$_.Exception.Message} }
        finally { if ($null -ne $inputStream) { $inputStream.Dispose() } }
    }
    $entry=$zip.CreateEntry('report-manifest.json');$entryStream=$entry.Open()
    try { $data=[Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 6));$entryStream.Write($data,0,$data.Length) } finally { $entryStream.Dispose() }
} finally { $zip.Dispose();$stream.Dispose() }
[ordered]@{archive=$report;created=$manifest.created;files=$manifest.files.Count;skipped=$manifest.skipped.Count} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'latest-debug-report.json') -Encoding UTF8
Write-Output $report
