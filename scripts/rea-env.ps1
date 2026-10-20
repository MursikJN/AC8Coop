$ErrorActionPreference = 'Stop'
$labRoot = Split-Path $PSScriptRoot -Parent
$nodeDir = 'C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'
$env:PATH = $nodeDir + ';' + $env:PATH
$env:GHIDRA_INSTALL_DIR = Join-Path $labRoot '.tools\ghidra_12.1.4_PUBLIC'
$jdkDirs = @(Get-ChildItem (Join-Path $labRoot '.tools') -Directory -Filter 'jdk-21*')
if ($jdkDirs.Count -ne 1) { throw 'Expected exactly one local JDK 21 installation.' }
$env:JAVA_HOME = $jdkDirs[0].FullName
$env:REA_ANALYSIS_PROVIDER = 'ghidra'
$env:GHIDRA_HEADLESS_MAXMEM = '4G'
$env:REA_GHIDRA_STARTUP_TIMEOUT_MS = '330000'
$reaNode = Join-Path $nodeDir 'node.exe'
$reaEntry = Join-Path $labRoot '.tools\node_modules\rea-agents\scripts\rea.mjs'
foreach ($required in @($reaNode, $reaEntry, (Join-Path $env:JAVA_HOME 'bin\javac.exe'), (Join-Path $env:GHIDRA_INSTALL_DIR 'support\analyzeHeadless.bat'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing tool: $required" }
}
