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
#include "menu_route_contract.h"
#include "mission_pause_lease.h"
namespace {
uintptr_t base=0,manager=0;DWORD thread=0;std::wstring output;
std::array<unsigned char,40> saved{};int32_t serial_saved=0;ac8pause::Lease lease;
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
 if(GetEnvironmentVariableW(L"AC8_MISSION_SYNC",marker,32)!=8||wcscmp(marker,L"25201480"))return false;
 auto n=GetEnvironmentVariableW(L"AC8_COOP_RECON_OUTPUT",path,32768);if(!n||n>=32768)return false;output=path;
 if(!GetModuleFileNameW(nullptr,exe,32768))return false;auto last=wcsrchr(exe,L'\\');if(!last||_wcsicmp(last+1,L"AceCombat8.exe"))return false;
 if(!thread)thread=GetCurrentThreadId();if(thread!=GetCurrentThreadId())return false;
 base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));unsigned char code[16]{};
 if(!bytes(base+0x79163f0,code,16)||!ac8route::fingerprint(code,"40574883ec2080793800488bf90f849b00"))return false;
 HMODULE self=nullptr;return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&setup),&self)!=0;
}
void dispatch(){
 if(!setup())return;
 FILE*f=_wfsopen((output+L"\\mission-pause-request.tsv").c_str(),L"r",_SH_DENYWR);if(!f)return;
 unsigned long long address=0;char op[16]{};int count=fscanf_s(f,"object\t%llx\nop\t%15s",&address,op,static_cast<unsigned>(sizeof op));fclose(f);
 std::array<unsigned char,40>head{};int32_t serial=0;uintptr_t table=0,owner=0,backlink=0;
 uint32_t flags=0,applied=0,override_count=0;unsigned char paused=0;
 bool ok=count==2&&identity(static_cast<uintptr_t>(address),head,serial)&&read(address,table)&&table==base+0xc9c0ef0&&read(address+0x20,owner)&&read(owner+0x870,backlink)&&backlink==address&&read(address+0x28,flags)&&read(address+0x34,override_count);
 const char*reason="identity_or_build";
 if(ok&&manager){ok=manager==address&&serial==serial_saved&&!memcmp(head.data()+12,saved.data()+12,28);reason="identity_changed";}
 if(ok){
  if(!strcmp(op,"acquire")){
   ok=override_count==0&&lease.acquire(flags);reason=ok?"held":"existing_pause_or_override";
   if(ok){manager=static_cast<uintptr_t>(address);saved=head;serial_saved=serial;ok=apply(manager,flags);}
  }else if(!strcmp(op,"release")){if(lease.held){lease.release(flags);ok=apply(static_cast<uintptr_t>(address),flags);}reason="released";}
  else if(!strcmp(op,"poll"))reason="observed";
  else{ok=false;reason="operation";}
  read(address+0x28,flags);read(address+0x2c,applied);read(address+0x30,paused);
  if(ok&&lease.held)ok=(flags&8)&&(applied&8)&&paused==1;
 }
 f=_wfsopen((output+L"\\mission-pause-status.tsv").c_str(),L"w",_SH_DENYWR);if(f){fprintf(f,"ok\t%d\nreason\t%s\nobject\t0x%llx\nheld\t%d\nflags\t%u\napplied\t%u\npaused\t%u\noverride\t%u\ntick\t%llu\n",ok?1:0,reason,address,lease.held?1:0,flags,applied,paused,override_count,GetTickCount64());fclose(f);}
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_mission_pause(void*){dispatch();return 0;}
