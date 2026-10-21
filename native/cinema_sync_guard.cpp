// Build 25201480 only. Per-instance vtable copy gates the stock hold-complete
// decision; it does not patch executable pages, input, threshold or callback data.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <array>
#include <map>
#include <memory>
#include <cstdio>
#include <cwchar>
#include <cstring>
#include <cmath>
#include <share.h>
#include "menu_route_contract.h"
#include "cinema_vote_gate.h"
namespace {
uintptr_t base=0;DWORD thread=0;std::wstring output;
constexpr uintptr_t table_rva=0xca4dea8,unguide_table_rva=0xca4e440,check_rva=0x7a5e7f0;
constexpr size_t check_slot=95;
using Decision=bool(__fastcall*)(uintptr_t,float);
struct Entry:ac8cinema::Gate {uintptr_t object=0,original_table=0;std::array<unsigned char,40> header{};int32_t serial=0;std::array<uintptr_t,129> table{};float threshold=0,treat=0;};
std::map<uintptr_t,std::unique_ptr<Entry>> entries;
void event(const char*kind,const Entry&e,bool stock_complete){
 FILE*f=_wfsopen((output+L"\\cinema-guard-events.tsv").c_str(),L"a",_SH_DENYWR);if(f){fprintf(f,"%llu\t%s\tscene=%u\tobject=0x%llx\tstock_complete=%d\n",GetTickCount64(),kind,e.scene,static_cast<unsigned long long>(e.object),stock_complete?1:0);fclose(f);}
}
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
bool same(Entry&e){std::array<unsigned char,40>head{};int32_t serial=0;return identity(e.object,head,serial)&&serial==e.serial&&!memcmp(head.data()+12,e.header.data()+12,28);}
bool __fastcall decide(uintptr_t o,float delta){
 auto it=entries.find(o);if(it==entries.end()||GetCurrentThreadId()!=thread)return false;
 auto&e=*it->second;if(!same(e))return false;
 const bool complete=reinterpret_cast<Decision>(base+check_rva)(o,delta);
 const bool prior=e.requested;const bool release=e.decide(complete);
 if(!prior&&e.requested)event("hold_vote",e,complete);
 if(release)event("skip_once",e,complete);
 return release;
}
bool env(const wchar_t*k,wchar_t*v,DWORD n){auto r=GetEnvironmentVariableW(k,v,n);return r>0&&r<n;}
bool setup(){
 wchar_t marker[32]{},path[32768]{},self[32768]{};
 if(!env(L"AC8_MISSION_SYNC",marker,32)||wcscmp(marker,L"25201480")||!env(L"AC8_COOP_RECON_OUTPUT",path,32768))return false;
 if(!GetModuleFileNameW(nullptr,self,32768))return false;auto last=wcsrchr(self,L'\\');if(!last||_wcsicmp(last+1,L"AceCombat8.exe"))return false;
 HMODULE module=nullptr;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&setup),&module))return false;
 if(!thread)thread=GetCurrentThreadId();if(thread!=GetCurrentThreadId())return false;
 base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));output=path;
 unsigned char code[16]{};uintptr_t slot=0;
 return bytes(base+check_rva,code,16)&&ac8route::fingerprint(code,"40534883ec30488b01488bd90f297424")&&read(base+table_rva+check_slot*8,slot)&&slot==base+check_rva&&read(base+unguide_table_rva+check_slot*8,slot)&&slot==base+check_rva;
}
void dispatch(){
 if(!setup()){
  if(!output.empty()){FILE*f=_wfsopen((output+L"\\cinema-guard-status.tsv").c_str(),L"w",_SH_DENYWR);if(f){fprintf(f,"ok\t0\nreason\tbuild_or_environment_contract\n");fclose(f);}}
  return;
 }
 FILE*f=_wfsopen((output+L"\\cinema-guard-request.tsv").c_str(),L"r",_SH_DENYWR);if(!f)return;
 unsigned long long address=0;unsigned scene=0,voting=0,authorize=0;char op[16]{};
 const int count=fscanf_s(f,"object\t%llx\nscene\t%u\nvoting\t%u\nauthorize\t%u\nop\t%15s",&address,&scene,&voting,&authorize,op,static_cast<unsigned>(sizeof op));fclose(f);
 bool ok=count==5&&scene>0&&voting<=1&&authorize<=1;const char*reason="request";Entry*e=nullptr;
 if(ok){
  auto it=entries.find(static_cast<uintptr_t>(address));
  if(it==entries.end()&&!strcmp(op,"install")&&entries.size()<32){
   auto p=std::make_unique<Entry>();p->object=static_cast<uintptr_t>(address);uintptr_t table=0,owner=0,backlink=0;
   ok=identity(p->object,p->header,p->serial)&&read(p->object,table)&&(table==base+table_rva||table==base+unguide_table_rva)&&read(p->object+0x20,owner)&&read(owner+0xa8,backlink)&&backlink==p->object&&read(p->object+0x7c,p->threshold)&&read(p->object+0x80,p->treat)&&std::isfinite(p->threshold)&&p->threshold>0&&p->threshold<10&&std::isfinite(p->treat)&&p->treat>=0&&p->treat<10&&bytes(table-sizeof(uintptr_t),p->table.data(),sizeof(p->table));
   reason="identity_or_threshold";
   if(ok){p->original_table=table;p->table[check_slot+1]=reinterpret_cast<uintptr_t>(&decide);e=p.get();entries.emplace(e->object,std::move(p));*reinterpret_cast<uintptr_t*>(e->object)=reinterpret_cast<uintptr_t>(e->table.data()+1);reason="installed";}
  }else if(it!=entries.end())e=it->second.get();else{ok=false;reason="not_installed";}
  if(ok&&e){
   uintptr_t current=0;ok=same(*e)&&read(e->object,current)&&current==reinterpret_cast<uintptr_t>(e->table.data()+1);reason=ok?"guarded":"identity_changed";
   if(ok){
    if(!strcmp(op,"restore")){*reinterpret_cast<uintptr_t*>(e->object)=e->original_table;e->voting=false;e->authorized=false;reason="restored";}
    else if(!strcmp(op,"install")||!strcmp(op,"poll")){
     if(!e->configure(scene,voting!=0,authorize!=0)){ok=false;reason="stale_scene";}
    }else{ok=false;reason="operation";}
   }
  }
 }
 f=_wfsopen((output+L"\\cinema-guard-status.tsv").c_str(),L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"ok\t%d\nreason\t%s\nobject\t0x%llx\nscene\t%u\nrequested\t%d\nconsumed\t%d\nthreshold\t%.9g\ntreat\t%.9g\ntick\t%llu\n",ok?1:0,reason,address,scene,e&&e->requested?1:0,e&&e->consumed?1:0,e?e->threshold:0,e?e->treat:0,GetTickCount64());fclose(f);
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_cinema_guard(void*){dispatch();return 0;}
