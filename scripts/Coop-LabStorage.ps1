# Compact lab primitives. Original archive content/attributes/ACLs are never written.
function Initialize-CoopStorageNative {
 if('Ac8CompactFiles' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Ac8CompactFiles {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 [return:MarshalAs(UnmanagedType.I1)]
 static extern bool CreateSymbolicLinkW(string link,string target,int flags);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 static extern uint GetFinalPathNameByHandleW(SafeFileHandle h,StringBuilder path,uint size,uint flags);
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME created,accessed,written;
  public uint volume,sizeHigh,sizeLow,links,indexHigh,indexLow;
 }
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info info);
 public static int Link(string link,string target) {
  if(CreateSymbolicLinkW(link,target,2))return 0;
  int error=Marshal.GetLastWin32Error();
  if(error==87 && CreateSymbolicLinkW(link,target,0))return 0;
  return error==87?Marshal.GetLastWin32Error():error;
 }
 public static string FinalPath(FileStream file) {
  var path=new StringBuilder(32768); uint n=GetFinalPathNameByHandleW(file.SafeFileHandle,path,(uint)path.Capacity,0);
  if(n==0 || n>=path.Capacity)throw new IOException("Cannot resolve archive file handle");
  string value=path.ToString();
  if(value.StartsWith(@"\\?\UNC\"))return @"\\"+value.Substring(8);
  return value.StartsWith(@"\\?\")?value.Substring(4):value;
 }
 public static string Identity(FileStream file) {
  Info info;if(!GetFileInformationByHandle(file.SafeFileHandle,out info))throw new IOException("Cannot identify file");
  return info.volume.ToString("x8")+":"+info.indexHigh.ToString("x8")+info.indexLow.ToString("x8");
 }
 public static uint LinkCount(FileStream file) {
  Info info;if(!GetFileInformationByHandle(file.SafeFileHandle,out info))throw new IOException("Cannot count file links");
  return info.links;
 }
}
'@ -ErrorAction Stop
}
function Test-CoopArchiveRelative {
 param([string]$Relative)
 return $Relative -match '^Game[\\/]Content[\\/]Paks[\\/][^:]+\.(pak|utoc|ucas|sig)$' -and $Relative -notmatch '(^|[\\/])\.\.([\\/]|$)' -and ![IO.Path]::IsPathRooted($Relative)
}
function Close-CoopArchiveGuard {
 param($Guard)
 if($Guard){foreach($stream in $Guard.Streams){$stream.Dispose()}}
}
function Open-CoopArchiveGuard {
 param([string]$Root,$Marker)
 Initialize-CoopStorageNative
 $lab=[IO.Path]::GetFullPath((Join-Path $Root 'lab-game'));$source=[IO.Path]::GetFullPath($Marker.source).TrimEnd([char[]]@('\','/'))
 Assert-CoopPlainPath $source;Assert-CoopPlainPath $lab
 $streams=New-Object 'System.Collections.Generic.List[System.IO.FileStream]';$seen=@{}
 try{
  foreach($entry in $Marker.archives){
   $relative=[string]$entry.path
   if(!(Test-CoopArchiveRelative $relative) -or $seen.ContainsKey($relative)){throw 'Invalid/duplicate compact archive entry'};$seen[$relative]=$true
   $original=[IO.Path]::GetFullPath((Join-Path $source $relative));$link=[IO.Path]::GetFullPath((Join-Path $lab $relative))
   if(!$original.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or !$link.StartsWith($lab+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compact archive escaped root'}
   Assert-CoopPlainPath $original;Assert-CoopPlainPath (Split-Path $link -Parent)
   $item=Get-Item -LiteralPath $link -Force
   if($item.PSIsContainer -or !($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkType -ne 'SymbolicLink'){throw ('Compact archive must be a file symlink: '+$relative)}
   # Both handles use FileShare.Read to reject data write/delete through links.
   $originalStream=[IO.File]::Open($original,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$streams.Add($originalStream)
   $linkStream=[IO.File]::Open($link,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$streams.Add($linkStream)
   if(![string]::Equals([Ac8CompactFiles]::FinalPath($linkStream),$original,[StringComparison]::OrdinalIgnoreCase) -or [Ac8CompactFiles]::Identity($linkStream) -ne [Ac8CompactFiles]::Identity($originalStream)){throw ('Compact archive target mismatch: '+$relative)}
   $sourceInfo=Get-Item -LiteralPath $original -Force
   if($originalStream.Length -ne [long]$entry.bytes -or $sourceInfo.LastWriteTimeUtc.Ticks -ne [long]$entry.write_ticks){throw ('Source archive changed; prepare a fresh kit after Steam updates: '+$relative)}
  }
  if(!$streams.Count){throw 'Compact archive list is empty'}
  return [pscustomobject]@{Streams=$streams;ArchiveCount=$seen.Count;Mode='compact'}
 }catch{foreach($stream in $streams){$stream.Dispose()};throw}
}
function Assert-CoopLabTree {
 param([string]$Root,$Marker)
 $lab=[IO.Path]::GetFullPath((Join-Path $Root 'lab-game'));$allowed=@{}
 Initialize-CoopStorageNative
 if($Marker.storage_mode -eq 'compact'){foreach($entry in $Marker.archives){if(!(Test-CoopArchiveRelative $entry.path) -or $allowed.ContainsKey($entry.path)){throw 'Invalid archive list'};$allowed[$entry.path]=$true}}
 $queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($lab);$found=0
 while($queue.Count){$dir=$queue.Dequeue();foreach($item in Get-ChildItem -LiteralPath $dir -Force){
  $relative=$item.FullName.Substring($lab.Length+1).Replace('\','/')
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
   if($item.PSIsContainer -or !$allowed.ContainsKey($relative) -or $item.LinkType -ne 'SymbolicLink'){throw ('Unexpected link in lab: '+$relative)};$found++
  }elseif($item.PSIsContainer){$queue.Enqueue($item.FullName)}elseif($allowed.ContainsKey($relative)){throw ('Archive link replaced by plain file: '+$relative)}else{
   $plain=$null;try{$plain=[IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);if([Ac8CompactFiles]::LinkCount($plain) -ne 1){throw ('Hardlink not allowed in copied lab files: '+$relative)}}finally{if($plain){$plain.Dispose()}}
  }
 }}
 if($found -ne $allowed.Count){throw 'Missing compact archive links'}
}
function Assert-CoopSeparateBinary {
 param([string]$Copy,[string]$Original)
 Initialize-CoopStorageNative;Assert-CoopPlainPath $Copy;Assert-CoopPlainPath $Original
 $a=$null;$b=$null
 try{
  $a=[IO.File]::Open($Copy,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  $b=[IO.File]::Open($Original,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  if([Ac8CompactFiles]::Identity($a) -eq [Ac8CompactFiles]::Identity($b)){throw 'Lab binary aliases original (hardlink forbidden)'}
 }finally{if($a){$a.Dispose()};if($b){$b.Dispose()}}
}
function New-CoopArchiveLink {
 param([string]$Link,[string]$Original)
 Initialize-CoopStorageNative
 $errorCode=[Ac8CompactFiles]::Link($Link,$Original)
 if($errorCode -ne 0){throw ('Cannot create compact file link (Win32 '+$errorCode+'). Run Prepare-Lab.cmd as administrator once; originals are not modified.')}
}
