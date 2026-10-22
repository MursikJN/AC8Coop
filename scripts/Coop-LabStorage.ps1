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
 static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint mode,uint flags,IntPtr template);
 [StructLayout(LayoutKind.Sequential)] struct Attributes {
  public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME created,accessed,written;
  public uint high,low;
 }
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 static extern bool GetFileAttributesExW(string path,int level,out Attributes data);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 static extern uint GetFinalPathNameByHandleW(SafeFileHandle h,StringBuilder path,uint size,uint flags);
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME created,accessed,written;
  public uint volume,sizeHigh,sizeLow,links,indexHigh,indexLow;
 }
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info info);
 public static SafeFileHandle OpenDirectory(string path,bool reparse) {
  var h=CreateFileW(path,0x80000000,1,IntPtr.Zero,3,reparse?0x02200000u:0x02000000u,IntPtr.Zero);
  if(h.IsInvalid){int e=Marshal.GetLastWin32Error();h.Dispose();throw new System.ComponentModel.Win32Exception(e,"Cannot guard archive directory");}
  return h;
 }
 public static long MetadataSize(string path) {
  Attributes data;if(!GetFileAttributesExW(path,0,out data))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  if((data.attributes&0x410)!=0)throw new IOException("Archive must be a regular file through Paks junction");
  return ((long)data.high<<32)|data.low;
 }
 public static string FinalPath(FileStream file) {
  return FinalPathHandle(file.SafeFileHandle);
 }
 public static string FinalPathHandle(SafeFileHandle handle) {
  var path=new StringBuilder(32768); uint n=GetFinalPathNameByHandleW(handle,path,(uint)path.Capacity,0);
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
 if($Guard){foreach($stream in $Guard.Streams){$stream.Dispose()};foreach($handle in $Guard.Directories){$handle.Dispose()}}
}
function Assert-CoopArchiveInventory {
 param([string]$Paks,$Marker)
 $allowed=@{};foreach($entry in $Marker.archives){
  if(!(Test-CoopArchiveRelative $entry.path) -or $allowed.ContainsKey($entry.path)){throw 'Invalid/duplicate compact archive entry'}
  $allowed[$entry.path]=$true
 }
 $sourcePaks=Join-Path $Marker.source 'Game/Content/Paks';Assert-CoopPlainPath $sourcePaks
 $found=0;$queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($sourcePaks)
 while($queue.Count){foreach($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked content in source Paks is forbidden'}
  if($item.PSIsContainer){$queue.Enqueue($item.FullName)}else{
   $relative='Game/Content/Paks/'+$item.FullName.Substring($sourcePaks.Length+1).Replace('\','/')
   if(!$allowed.ContainsKey($relative)){throw ('Unexpected source Paks file: '+$relative)};$found++
  }
 }}
 if(!$found -or $found -ne $allowed.Count){throw 'Missing source archives'}
}
function Open-CoopArchiveGuard {
 param([string]$Root,$Marker)
 Initialize-CoopStorageNative
 $lab=[IO.Path]::GetFullPath((Join-Path $Root 'lab-game'));$source=[IO.Path]::GetFullPath($Marker.source).TrimEnd([char[]]@('\','/'))
 Assert-CoopPlainPath $source;Assert-CoopPlainPath $lab
 $streams=New-Object 'System.Collections.Generic.List[System.IO.FileStream]';$seen=@{}
 $directories=New-Object 'System.Collections.Generic.List[Microsoft.Win32.SafeHandles.SafeFileHandle]'
 try{
  $paks=Join-Path $lab 'Game/Content/Paks';$sourcePaks=Join-Path $source 'Game/Content/Paks'
  Assert-CoopPlainPath (Split-Path $paks -Parent);Assert-CoopPlainPath $sourcePaks
  $item=Get-Item -LiteralPath $paks -Force
  if(!$item.PSIsContainer -or !($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkType -ne 'Junction'){throw 'Compact Paks must be the verified directory junction; run Repair-Lab.cmd for compact-1'}
  # Guard the junction itself, its target and the original directory against replacement.
  $junctionHandle=[Ac8CompactFiles]::OpenDirectory($paks,$true);$directories.Add($junctionHandle)
  $targetHandle=[Ac8CompactFiles]::OpenDirectory($paks,$false);$directories.Add($targetHandle)
  $sourceHandle=[Ac8CompactFiles]::OpenDirectory($sourcePaks,$false);$directories.Add($sourceHandle)
  if(![string]::Equals([Ac8CompactFiles]::FinalPathHandle($targetHandle),$sourcePaks,[StringComparison]::OrdinalIgnoreCase)){throw 'Compact Paks target mismatch'}
  Assert-CoopArchiveInventory -Paks $paks -Marker $Marker
  foreach($entry in $Marker.archives){
   $relative=[string]$entry.path
   if(!(Test-CoopArchiveRelative $relative) -or $seen.ContainsKey($relative)){throw 'Invalid/duplicate compact archive entry'};$seen[$relative]=$true
   $original=[IO.Path]::GetFullPath((Join-Path $source $relative));$link=[IO.Path]::GetFullPath((Join-Path $lab $relative))
   if(!$original.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or !$link.StartsWith($lab+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compact archive escaped root'}
   Assert-CoopPlainPath $original
   $item=Get-Item -LiteralPath $link -Force
   if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ('Archive inside Paks must be a regular file: '+$relative)}
   # Both handles use FileShare.Read to reject data write/delete through links.
   $originalStream=[IO.File]::Open($original,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$streams.Add($originalStream)
   $linkStream=[IO.File]::Open($link,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$streams.Add($linkStream)
   if(![string]::Equals([Ac8CompactFiles]::FinalPath($linkStream),$original,[StringComparison]::OrdinalIgnoreCase) -or [Ac8CompactFiles]::Identity($linkStream) -ne [Ac8CompactFiles]::Identity($originalStream)){throw ('Compact archive target mismatch: '+$relative)}
   $sourceInfo=Get-Item -LiteralPath $original -Force
   if($originalStream.Length -ne [long]$entry.bytes -or $sourceInfo.LastWriteTimeUtc.Ticks -ne [long]$entry.write_ticks){throw ('Source archive changed; prepare a fresh kit after Steam updates: '+$relative)}
   if([Ac8CompactFiles]::MetadataSize($link) -ne [long]$entry.bytes){throw ('Win32 archive size mismatch: '+$relative)}
  }
  if(!$streams.Count){throw 'Compact archive list is empty'}
  return [pscustomobject]@{Streams=$streams;Directories=$directories;ArchiveCount=$seen.Count;Mode='compact';Layout='paks-junction-v1'}
 }catch{foreach($stream in $streams){$stream.Dispose()};foreach($handle in $directories){$handle.Dispose()};throw}
}
function Assert-CoopLabTree {
 param([string]$Root,$Marker)
 $lab=[IO.Path]::GetFullPath((Join-Path $Root 'lab-game'));$compact=$Marker.storage_mode -eq 'compact'
 Initialize-CoopStorageNative
 $queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($lab);$found=0
 while($queue.Count){$dir=$queue.Dequeue();foreach($item in Get-ChildItem -LiteralPath $dir -Force){
  $relative=$item.FullName.Substring($lab.Length+1).Replace('\','/')
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
   if(!$compact -or $relative -ne 'Game/Content/Paks' -or !$item.PSIsContainer -or $item.LinkType -ne 'Junction'){throw ('Unexpected link in lab: '+$relative)};$found++
  }elseif($compact -and $relative -eq 'Game/Content/Paks'){throw 'Old compact file-link layout; run Repair-Lab.cmd'}elseif($item.PSIsContainer){$queue.Enqueue($item.FullName)}else{
   $plain=$null;try{$plain=[IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);if([Ac8CompactFiles]::LinkCount($plain) -ne 1){throw ('Hardlink not allowed in copied lab files: '+$relative)}}finally{if($plain){$plain.Dispose()}}
  }
 }}
 if($found -ne $(if($compact){1}else{0})){throw 'Missing compact Paks junction'}
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
function New-CoopPaksJunction {
 param([string]$Link,[string]$Original)
 Assert-CoopPlainPath (Split-Path $Link -Parent);Assert-CoopPlainPath $Original
 if(Test-Path -LiteralPath $Link){throw 'Paks junction destination already exists'}
 New-Item -ItemType Junction -Path $Link -Value $Original -ErrorAction Stop|Out-Null
}
