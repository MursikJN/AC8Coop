// Exact build 25201480. Own one stock pause reason; run the stock manager.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <share.h>
#include <string>
#include <ctime>
#include "menu_route_contract.h"
#include "mission_pause_lease.h"
#include "adapter_bridge_io.h"
#include "adapter_bootstrap_contract.h"
namespace {
uintptr_t base=0,manager=0;DWORD thread=0;std::wstring output;
std::array<unsigned char,40> saved{};int32_t serial_saved=0;ac8pause::Lease lease;
const char*bootstrap_reason="bootstrap_not_checked";
bool bytes(uintptr_t p,void*out,size_t n){if(p<0x10000||p+n>=0x800000000000ULL||!n||n>4096)return false;__try{memcpy(out,reinterpret_cast<void*>(p),n);return true;}__except(EXCEPTION_EXECUTE_HANDLER){return false;}}
template<class T>bool read(uintptr_t p,T&v){return bytes(p,&v,sizeof v);}
bool identity(uintptr_t o,std::array<unsigned char,40>&head,int32_t&serial){
 if(o%8||!bytes(o,head.data(),head.size()))return false;
 int32_t index=0,count=0;uint32_t flags=0;uintptr_t array=0,chunk=0,actual=0;
 memcpy(&index,head.data()+12,4);memcpy(&flags,head.data()+8,4);
 if(flags&0x60000010||index<0||!read(base+0xdc60cd0+0x24,count)||index>=count||count>0x1000000||!read(base+0xdc60cd0+0x10,array)||!read(array+(index/65536)*8,chunk))return false;
 const auto item=chunk+(index&65535)*0x18;
 return read(item,actual)&&actual==o&&read(item+0x10,serial)&&serial>=0;
}
bool apply(uintptr_t o,uint32_t flags){__try{
 *reinterpret_cast<uint32_t*>(o+0x28)=flags;*reinterpret_cast<unsigned char*>(o+0x38)=1;
 reinterpret_cast<void(__fastcall*)(uintptr_t)>(base+0x79163f0)(o);return true;
 }__except(EXCEPTION_EXECUTE_HANDLER){return false;}}
bool setup(){
 wchar_t marker[32]{},path[32768]{},exe[32768]{};
 output.clear();bootstrap_reason="bootstrap_output";
 auto n=GetEnvironmentVariableW(L"AC8_COOP_RECON_OUTPUT",path,32768);if(!n||n>=32768)return false;output=path;
 bootstrap_reason="bootstrap_environment";
 if(GetEnvironmentVariableW(L"AC8_MISSION_SYNC",marker,32)!=8||wcscmp(marker,L"25201480"))return false;
 bootstrap_reason="bootstrap_process";
 if(!GetModuleFileNameW(nullptr,exe,32768))return false;auto last=wcsrchr(exe,L'\\');if(!last||_wcsicmp(last+1,L"AceCombat8.exe"))return false;
 bootstrap_reason="bootstrap_thread";
 if(!thread)thread=GetCurrentThreadId();if(thread!=GetCurrentThreadId())return false;
 base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));unsigned char code[16]{};
 bootstrap_reason="bootstrap_fingerprint";
 if(!bytes(base+0x79163f0,code,16)||!ac8route::fingerprint(code,ac8adapter::pause_update_fingerprint))return false;
 bootstrap_reason="bootstrap_module";HMODULE self=nullptr;
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&setup),&self))return false;
 bootstrap_reason="bootstrap_ready";return true;
}
void status(bool ok,const char*reason,const std::string&stamp,unsigned long long address=0,uint32_t flags=0,uint32_t applied=0,unsigned char paused=0,uint32_t override_count=0){
 const auto temp=output+L"\\mission-pause-status.tmp",path=output+L"\\mission-pause-status.tsv";
 FILE*f=_wfsopen(temp.c_str(),L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"format\tac8-mission-pause-v2\nstamp\t%s\nok\t%d\nreason\t%s\nobject\t0x%llx\nheld\t%d\nflags\t%u\napplied\t%u\npaused\t%u\noverride\t%u\ntick\t%llu\n",stamp.c_str(),ok?1:0,reason,address,lease.held?1:0,flags,applied,paused,override_count,GetTickCount64());
 fclose(f);MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
void dispatch(){
 if(!setup()){if(!output.empty())status(false,bootstrap_reason,ac8adapter::echo(output+L"\\mission-pause-request.tsv"));return;}
 std::map<std::string,std::string>fields;
 if(!ac8adapter::request(output+L"\\mission-pause-request.tsv",fields)){status(false,"request_fields","");return;}
 const auto stamp=fields["stamp"];unsigned long long address=0,created=0;const auto now=static_cast<unsigned long long>(time(nullptr));
 if(fields.size()!=5||fields["format"]!="ac8-mission-pause-v2"||!ac8adapter::stamp_valid(stamp)||!ac8adapter::number(fields["object"],address)||!ac8adapter::number(fields["created_unix"],created)||created>now||now-created>3){status(false,"request_contract",stamp);return;}
 const auto&op=fields["op"];
 if(op=="bootstrap"){status(address==0,address==0?"bootstrap_ready":"request_contract",stamp);return;}
 if(op!="acquire"&&op!="release"&&op!="poll"){status(false,"operation",stamp,address);return;}
 std::array<unsigned char,40>head{};int32_t serial=0;uintptr_t table=0,owner=0,backlink=0;
 uint32_t flags=0,applied=0,override_count=0;unsigned char paused=0;
 bool ok=identity(static_cast<uintptr_t>(address),head,serial)&&read(address,table)&&table==base+0xc9c0ef0&&read(address+0x20,owner)&&read(owner+0x870,backlink)&&backlink==address&&read(address+0x28,flags)&&read(address+0x34,override_count);
 const char*reason="identity_or_build";
 if(ok&&manager){ok=manager==address&&serial==serial_saved&&!memcmp(head.data()+12,saved.data()+12,28);reason="identity_changed";}
 if(ok){
  if(op=="acquire"){
   ok=override_count==0&&lease.acquire(flags);reason=ok?"held":"existing_pause_or_override";
   if(ok){manager=static_cast<uintptr_t>(address);saved=head;serial_saved=serial;ok=apply(manager,flags);}
  }else if(op=="release"){if(lease.held){lease.release(flags);ok=apply(static_cast<uintptr_t>(address),flags);}reason="released";}
  else if(op=="poll")reason="observed";
  else{ok=false;reason="operation";}
  read(address+0x28,flags);read(address+0x2c,applied);read(address+0x30,paused);
  if(ok&&lease.held)ok=(flags&8)&&(applied&8)&&paused==1;
 }
 status(ok,reason,stamp,address,flags,applied,paused,override_count);
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_mission_pause(void*){dispatch();return 0;}
