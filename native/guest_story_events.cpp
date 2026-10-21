// Development bridge for a preserved Unit whose AI arrays are empty. The
// original execution always runs for all ordinary mission units. No player
// pointer is returned through LiveAIGameObject or inserted into AI containers.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <array>
#include <vector>
#include <map>
#include <string>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <ctime>
#include <cerrno>
#include <cmath>
#include "guest_story_route.h"
#ifndef AC8_STORY_REV
#define AC8_STORY_REV r19
#endif
#define AC8_STORY_STR_(x) #x
#define AC8_STORY_STR(x) AC8_STORY_STR_(x)
#define AC8_STORY_WIDEN_(x) L##x
#define AC8_STORY_WIDEN(x) AC8_STORY_WIDEN_(x)
#define AC8_STORY_REV_W AC8_STORY_WIDEN(AC8_STORY_STR(AC8_STORY_REV))
namespace {
uintptr_t base=0;DWORD owner=0;std::wstring output;const char* detail="not_bound";
struct Id{uintptr_t pointer=0;int32_t index=-1,serial=0;};
Id world,unit,player,controller,host,trial_plug,trial_wrapper;
bool bound=false,installed=false;unsigned seen=0,forwarded=0;uint64_t key=0;
float last_damage=0;
constexpr uintptr_t damage_vtable=0xc67f800,execute_offset=0x2b8,damage_execute=0x73f5770;
using Execute=void(__fastcall*)(uintptr_t,uintptr_t,uintptr_t,uintptr_t);
bool bytes(uintptr_t p,void*out,size_t n){
 if(p<0x10000||p>=0x800000000000ULL||!n||n>4096||p+n>=0x800000000000ULL)return false;
 __try{memcpy(out,reinterpret_cast<void*>(p),n);return true;}__except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
template<class T>bool read(uintptr_t p,T&v){return bytes(p,&v,sizeof v);}
bool identity(uintptr_t p,Id& out,bool allocate_serial=false){
 uintptr_t arr=0,chunk=0,actual=0;int32_t index=-1,count=0,serial=0;uint32_t flags=0;
 if(!read(p+12,index)||index<0||!read(p+8,flags)||(flags&0x60000010)||!read(base+0xdc60cd0+0x24,count)||index>=count||count>0x1000000||!read(base+0xdc60cd0+0x10,arr)||!read(arr+uintptr_t(index/65536)*8,chunk))return false;
 const auto item=chunk+uintptr_t(index&65535)*24;
 if(!read(item,actual)||actual!=p||!read(item+16,serial))return false;
 if(!serial&&allocate_serial){using Mint=int32_t(__fastcall*)(uintptr_t,int32_t);const auto minted=reinterpret_cast<Mint>(base+0x1aae560)(base+0xdc60cd0,index);if(!read(item+16,serial)||serial!=minted)return false;}
 if(serial<=0)return false;out={p,index,serial};return true;
}
bool same(const Id&i){Id now;return identity(i.pointer,now)&&now.index==i.index&&now.serial==i.serial;}
bool in_world(const Id&i){uintptr_t level=0,w=0;return same(i)&&read(i.pointer+0x20,level)&&read(level+0xc0,w)&&w==world.pointer;}
bool number(const std::string&s,uint64_t&v){if(s.empty()||s.size()>20||s[0]=='-'||s[0]=='+')return false;errno=0;char*e=nullptr;v=strtoull(s.c_str(),&e,0);return !errno&&e==s.c_str()+s.size();}
bool file(const wchar_t*name,std::map<std::string,std::string>&out){
 FILE*f=nullptr;if(_wfopen_s(&f,(output+L"\\"+name).c_str(),L"rb")||!f)return false;char b[4097]{};auto n=fread(b,1,4097,f);fclose(f);if(n>4096)return false;
 std::string text(b,n);size_t start=0;while(start<text.size()){auto end=text.find('\n',start);if(end==std::string::npos)return false;auto line=text.substr(start,end-start);start=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos||!out.emplace(line.substr(0,tab),line.substr(tab+1)).second)return false;}return true;
}
bool setup(){
 wchar_t mark[32]{},dir[32768]{},source[32768]{},path[32768]{},expected[32768]{};
 if(GetEnvironmentVariableW(L"AC8_LOCAL_ADAPTER_DEV",mark,32)!=8||wcscmp(mark,L"25201480")||!GetEnvironmentVariableW(L"AC8_COOP_RECON_OUTPUT",dir,32768)||!GetEnvironmentVariableW(L"AC8_LOCAL_SCRIPTS",source,32768))return false;
 HMODULE module=nullptr;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&setup),&module)||!GetModuleFileNameW(module,path,32768))return false;
 const auto target=std::wstring(source)+L"\\..\\..\\..\\ac8_guest_story_"+AC8_STORY_REV_W+L".dll";
 if(!GetFullPathNameW(target.c_str(),32768,expected,nullptr)||_wcsicmp(expected,path)||!GetModuleFileNameW(nullptr,path,32768))return false;
 const auto name=wcsrchr(path,L'\\');if(!name||_wcsicmp(name+1,L"AceCombat8.exe"))return false;
 if(!owner)owner=GetCurrentThreadId();if(owner!=GetCurrentThreadId())return false;
 base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));output=dir;return true;
}
bool graph(){
 uintptr_t p=0,c=0,vt=0;uint8_t active=0;
 if(!bound||GetCurrentThreadId()!=owner||!same(world)||!in_world(unit)||!in_world(player)||!in_world(host)||!same(controller)||
  !read(controller.pointer+0x2d0,p)||p!=host.pointer||!read(host.pointer+0x2c8,c)||c!=controller.pointer||
  !read(player.pointer,vt)||vt!=base+0xcc01cc8||!read(player.pointer+0x2c8,c)||c||!read(player.pointer+0x3f4,active)||active!=1)return false;
 for(unsigned o:{0x2c0u,0x2d0u,0x2e0u,0x2f0u,0x300u,0x310u}){int32_t n=-1;if(!read(unit.pointer+o+8,n)||n)return false;}
 return true;
}
bool selection(uintptr_t plug,uintptr_t wrapper){
 uintptr_t vt=0,data=0;int32_t n=0,cap=0;uint64_t wanted=0,group=0;
 if(!graph()||!read(plug,vt)||vt!=base+damage_vtable||!read(plug+0x58,wanted)||!read(plug+0x60,group)||
  !read(wrapper+0x28,data)||!read(wrapper+0x30,n)||!read(wrapper+0x34,cap)||n<0||n>4096||cap<n||cap>65536)return false;
 std::vector<uintptr_t>units;for(int i=0;i<n;++i){uintptr_t p=0;if(!read(data+uintptr_t(i)*8,p))return false;units.push_back(p);}
 std::vector<uint64_t>groups;if(!read(unit.pointer+0x1c8,data)||!read(unit.pointer+0x1d0,n)||!read(unit.pointer+0x1d4,cap)||n<0||n>128||cap<n||cap>4096)return false;
 for(int i=0;i<n;++i){uint64_t value=0;if(!read(data+uintptr_t(i)*8,value))return false;groups.push_back(value);}
 uint64_t current=0;return read(unit.pointer+0x358,current)&&current==key&&ac8story::selected(unit.pointer,units,key,groups,wanted,group);
}
void __fastcall execute(uintptr_t plug,uintptr_t b,uintptr_t c,uintptr_t wrapper){
 const bool route=selection(plug,wrapper);float amount=0;
 const bool valid=route&&read(plug+0x68,amount)&&std::isfinite(amount)&&amount>0;
 reinterpret_cast<Execute>(base+damage_execute)(plug,b,c,wrapper);
 if(valid&&graph()){
  ++seen;last_damage=0;
  // ModifyHealth intentionally refuses LivePlayerPlane (virtual +aa0 returns
  // true). Match Unit's native script-damage route instead: an initialized
  // damage event, the player's actual damage virtual, then stock destruction
  // of any event-owned engine arrays.
  alignas(16) unsigned char event[0x40]{};using Init=void*(__fastcall*)(void*,uintptr_t,uint8_t);
  reinterpret_cast<Init>(base+0x73a6180)(event,player.pointer,14);
  uint8_t invincible=0;read(player.pointer+0x3f8,invincible);
  using Invincible=void(__fastcall*)(uintptr_t,bool);reinterpret_cast<Invincible>(base+0x6d09390)(player.pointer,false);
  using Damage=float(__fastcall*)(uintptr_t,float,void*,uintptr_t,uintptr_t);
  const float changed=reinterpret_cast<Damage>(base+0x7d5a430)(player.pointer,amount,event,0,0);
  reinterpret_cast<Invincible>(base+0x6d09390)(player.pointer,invincible!=0);
  for(unsigned off:{0x30u,0x20u}){uintptr_t allocation=0;memcpy(&allocation,event+off,8);if(allocation){uintptr_t allocator=0,vt=0,free=0;
   if(read(base+0xe426090,allocator)&&read(allocator,vt)&&read(vt+0x48,free)){using Free=void(__fastcall*)(uintptr_t,uintptr_t);reinterpret_cast<Free>(free)(allocator,allocation);}
  }}
  if(std::isfinite(changed)&&changed>0){++forwarded;last_damage=changed;}
 }
}
bool patch(bool install){
 auto slot=reinterpret_cast<void* volatile*>(base+damage_vtable+execute_offset);DWORD previous=0;
 if(!VirtualProtect(const_cast<void**>(slot),8,PAGE_READWRITE,&previous))return false;
 void* original=reinterpret_cast<void*>(base+damage_execute);void* bridge=reinterpret_cast<void*>(&execute);
 const auto found=InterlockedCompareExchangePointer(slot,install?bridge:original,install?original:bridge);
 DWORD unused=0;const bool protection=VirtualProtect(const_cast<void**>(slot),8,previous,&unused)!=0;
 if(found==(install?original:bridge))installed=install;
 return found==(install?original:bridge)&&protection;
}
void report(){
 FILE*f=nullptr;if(_wfopen_s(&f,(output+L"\\guest-story-status-"+AC8_STORY_REV_W+L".tsv").c_str(),L"wb")||!f)return;
 std::fprintf(f,"reason\t%s\nbound\t%d\ninstalled\t%d\nselected_events\t%u\nforwarded_damage_events\t%u\nall_story_commands_bridged\t0\n",detail,bound?1:0,installed?1:0,seen,forwarded);fclose(f);
}
bool bind(){
 std::map<std::string,std::string>r,commit;uint64_t created=0;
 if(bound||!file(L"guest-story-request.tsv",r)||!number(r["created_unix"],created)||std::llabs(int64_t(time(nullptr))-int64_t(created))>3||!file(L"guest-role-commit-r19.tsv",commit)||commit["npc_retired_verified"]!="1"||commit["unit_preserved"]!="1"||commit["player_visible_active"]!="1")return false;
 for(const auto& pair:std::array<std::pair<const char*,Id*>,3>{{{"world",&world},{"unit",&unit},{"player",&player}}}){
  uint64_t p=0;if(!number(commit[pair.first],p)||!identity(p,*pair.second))return false;
  if(std::string(pair.first)!="world"){uint64_t index=0,serial=0;if(!number(commit[std::string(pair.first)+"_index"],index)||!number(commit[std::string(pair.first)+"_serial"],serial)||index!=uint32_t(pair.second->index)||serial!=uint32_t(pair.second->serial))return false;}
 }
 for(const auto& pair:std::array<std::pair<const char*,Id*>,2>{{{"controller",&controller},{"host",&host}}}){uint64_t p=0;if(!number(r[pair.first],p)||!identity(p,*pair.second))return false;}
 unsigned char actual[16]{};const unsigned char fingerprint[]={0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18,0x56,0x57,0x41,0x54,0x41,0x56};
 if(!bytes(base+damage_execute,actual,16)||memcmp(actual,fingerprint,16)||!read(unit.pointer+0x358,key))return false;
 const unsigned char signatures[][16]={
  {0x48,0x8b,0xc4,0x48,0x89,0x58,0x08,0x48,0x89,0x68,0x10,0x48,0x89,0x70,0x18,0x57},
  {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x30,0x48,0x63,0x59,0x08,0x48,0x8b},
  {0x48,0x83,0xec,0x38,0x48,0x8b,0x82,0xa0,0x01,0x00,0x00,0x48,0x85,0xc0,0x74,0x1e},
  {0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18,0x48,0x89,0x7c,0x24,0x20,0x41}};
 const uintptr_t functions[]={0x7d1ccb0,0x16c2e30,0x73a6180,0x7d5a430};
 for(unsigned i=0;i<4;++i)if(!bytes(base+functions[i],actual,16)||memcmp(actual,signatures[i],16))return false;
 uintptr_t vt=0,fn=0;if(!read(unit.pointer+0x2a0,vt)||!read(vt+0x18,fn)||fn!=base+0x6d0f270)return false;
 bound=true;if(!graph()||!patch(true)){bound=false;return false;}return true;
}
bool trial(){
 if(!graph()||!installed||trial_plug.pointer)return false;
 std::map<std::string,std::string>r;uint64_t p=0,created=0;
 if(!file(L"guest-story-trial.tsv",r)||!number(r["created_unix"],created)||std::llabs(int64_t(time(nullptr))-int64_t(created))>3||
  !number(r["plug"],p)||!identity(p,trial_plug,true)||!number(r["wrapper"],p)||!identity(p,trial_wrapper,true))return false;
 uintptr_t outer=0,vt=0,data=0,klass=0,cdo=0,expected_vt=0;int32_t n=0,cap=0;
 uint64_t wrapper_class=0;if(!number(r["wrapper_class"],wrapper_class)||!read(trial_wrapper.pointer+0x10,klass)||klass!=wrapper_class||!read(klass+0x110,cdo)||!read(cdo,expected_vt)||expected_vt<base||expected_vt>base+0xf000000||!read(trial_wrapper.pointer,vt)||vt!=expected_vt)return false;
 if(!read(trial_plug.pointer+0x20,outer)||outer!=world.pointer||!read(trial_wrapper.pointer+0x20,outer)||outer!=world.pointer||
  !read(trial_plug.pointer,vt)||vt!=base+damage_vtable||!read(trial_wrapper.pointer+0x28,data)||data||!read(trial_wrapper.pointer+0x30,n)||n||!read(trial_wrapper.pointer+0x34,cap)||cap)return false;
 // This is a real engine-allocated UObject array. Its destructor owns the
 // engine allocation; no stack/CRT buffer is exposed to GC.
 *reinterpret_cast<int32_t*>(trial_wrapper.pointer+0x30)=1;
 using Grow=void(__fastcall*)(uintptr_t,int32_t);reinterpret_cast<Grow>(base+0x16c2e30)(trial_wrapper.pointer+0x28,0);
 if(!read(trial_wrapper.pointer+0x28,data)||!data||!read(trial_wrapper.pointer+0x34,cap)||cap<1)return false;
 *reinterpret_cast<uintptr_t*>(data)=unit.pointer;
 *reinterpret_cast<uint64_t*>(trial_plug.pointer+0x58)=key;*reinterpret_cast<uint64_t*>(trial_plug.pointer+0x60)=0;
 *reinterpret_cast<int32_t*>(trial_plug.pointer+0x2c)=-1;*reinterpret_cast<float*>(trial_plug.pointer+0x68)=1.0f;
 int32_t before=0,after=0,restored=0;if(!read(player.pointer+0xda8,before)||before<100)return false;
 uintptr_t method=0;if(!read(base+damage_vtable+execute_offset,method)||method!=reinterpret_cast<uintptr_t>(&execute))return false;
 const auto calls=forwarded;const bool selected=selection(trial_plug.pointer,trial_wrapper.pointer);
 reinterpret_cast<Execute>(method)(trial_plug.pointer,0,0,trial_wrapper.pointer);
 const bool changed=read(player.pointer+0xda8,after)&&after<before&&forwarded==calls+1;
 if(after<before&&std::isfinite(last_damage)&&last_damage>0){using Heal=float(__fastcall*)(uintptr_t,float,uint8_t,uintptr_t,bool);reinterpret_cast<Heal>(base+0x7d5ab50)(player.pointer,last_damage,14,0,false);}
 const bool preserved=read(player.pointer+0xda8,restored)&&restored==before;
 *reinterpret_cast<int32_t*>(trial_wrapper.pointer+0x30)=0;
 FILE*f=nullptr;if(!_wfopen_s(&f,(output+L"\\guest-story-trial-"+AC8_STORY_REV_W+L".tsv").c_str(),L"wb")&&f){std::fprintf(f,"native_execution_vtable_dispatched\t1\nselected_role\t%d\nactual_damage_changed_player_health\t%d\nplayer_health_before_internal\t%d\nplayer_health_after_internal\t%d\nplayer_health_restored\t%d\n",selected?1:0,changed?1:0,before,after,preserved?1:0);fclose(f);}
 return changed&&preserved&&graph();
}
int dispatch(unsigned action){
 if(!setup())return 0;
 if(action==0)detail=bind()?"unit_damage_bridge_installed":"unit_damage_bridge_refused";
 if(action==1)detail=trial()?"native_unit_damage_routed_to_player_and_health_restored":"native_unit_damage_trial_unverified";
 if(action==2){const bool ok=!installed||patch(false);if(ok)bound=false;detail=ok?"unit_damage_bridge_removed":"unit_damage_bridge_remove_failed";}
 if(action==3)detail=graph()?"unit_damage_binding_valid":"unit_damage_binding_expired";
 report();return 0;
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_guest_story_bind(void*){return dispatch(0);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_guest_story_trial(void*){return dispatch(1);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_guest_story_unbind(void*){return dispatch(2);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_guest_story_poll(void*){return dispatch(3);}
