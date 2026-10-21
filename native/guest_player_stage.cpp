// Build 25201480: stage one deferred F-14D player actor with pre-init barriers.
// No FinishSpawning, AI switch, controller takeover, role-array writes or flight updates.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <ctime>
#include <map>
#include <string>
#include <cerrno>
#include <share.h>
namespace {
uintptr_t base=0;DWORD thread=0;std::wstring output;
bool attempted=false,receipt_seen=false,barrier=false,quarantine=false,retired=false;unsigned receipts=0,destroys=0;uint32_t stabilized_serials=0;
const char* reason="idle";
struct Identity{uintptr_t pointer=0;int32_t index=-1,serial=0;std::array<unsigned char,40>header{};};
Identity owned{},host{},pc{},npc{},unit{},world{},klass{},cdo{};uintptr_t raw=0;
bool pointer(uintptr_t p){return p>=0x10000&&p<0x800000000000ULL&&p%8==0;}
bool bytes(uintptr_t p,void*out,size_t n){
 if(p<0x10000)return false;if(p>=0x800000000000ULL||!n||n>4096||p+n>=0x800000000000ULL)return false;
 __try{memcpy(out,reinterpret_cast<void*>(p),n);return true;}__except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
template<class T>bool read(uintptr_t p,T&v){return bytes(p,&v,sizeof v);}
bool item(int32_t index,uintptr_t&out){int32_t count=0,chunks=0;uintptr_t array=0,chunk=0;
 if(index<0||!read(base+0xdc60cd0+0x24,count)||index>=count||count>0x1000000||!read(base+0xdc60cd0+0x2c,chunks)||chunks<=0||chunks>4096||index/65536>=chunks||!read(base+0xdc60cd0+0x10,array)||!pointer(array)||!read(array+static_cast<uintptr_t>(index/65536)*8,chunk)||!pointer(chunk))return false;
 out=chunk+static_cast<uintptr_t>(index&65535)*24;return true;
}
bool identify(uintptr_t p,Identity&id){Identity h;h.pointer=p;uintptr_t entry=0,actual=0;uint32_t flags=0;
 if(!pointer(p)||!bytes(p,h.header.data(),40))return false;memcpy(&h.index,h.header.data()+12,4);memcpy(&flags,h.header.data()+8,4);
 if(flags&0x60000000||!item(h.index,entry)||!read(entry,actual)||actual!=p||!read(entry+16,h.serial)||h.serial<0)return false;id=h;return true;
}
bool same(const Identity&id){Identity now;return identify(id.pointer,now)&&now.index==id.index&&now.serial==id.serial&&!memcmp(id.header.data(),now.header.data(),8)&&!memcmp(id.header.data()+12,now.header.data()+12,28);}
bool gone(){uintptr_t entry=0,actual=0;int32_t serial=0;return owned.serial>0&&item(owned.index,entry)&&read(entry,actual)&&read(entry+16,serial)&&(!actual||serial!=owned.serial);}
bool fingerprint(uintptr_t rva,const char*hex){unsigned char actual[16]{};if(!bytes(base+rva,actual,16))return false;for(unsigned i=0;i<16;++i){unsigned x=0;if(sscanf_s(hex+i*2,"%2x",&x)!=1||actual[i]!=x)return false;}return true;}
bool code(){return fingerprint(0x465a120,"40555356574154415541564157488dac")&&fingerprint(0x4263b80,"4889542410534883ec20488b4110488b")&&fingerprint(0x1aae560,"40574883ec203b1588271b0c7d1e0fb7")&&fingerprint(0x3fe0160,"48895c24084889742410574883ec20f6");}
void report(const char*state){FILE*f=_wfsopen((output+L"\\guest-player-stage.tsv").c_str(),L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"state\t%s\nreason\t%s\nattempted\t%d\nreceipts\t%u\nbarrier\t%d\nquarantine\t%d\nretired\t%d\nowned\t0x%llx\nindex\t%d\nserial\t%d\nfinish_called\t0\nai_mutated\t0\nrole_mutated\t0\nstabilized_serial_mask\t%u\n",state,reason,attempted?1:0,receipts,barrier?1:0,quarantine?1:0,retired?1:0,static_cast<unsigned long long>(raw),owned.index,owned.serial,stabilized_serials);fclose(f);
}
bool setup(){wchar_t marker[32]{},path[32768]{},source[32768]{},self[32768]{},expected[32768]{};
 if(!GetEnvironmentVariableW(L"AC8_LOCAL_ADAPTER_DEV",marker,32)||wcscmp(marker,L"25201480")||!GetEnvironmentVariableW(L"AC8_COOP_RECON_OUTPUT",path,32768)||!GetEnvironmentVariableW(L"AC8_LOCAL_SCRIPTS",source,32768))return false;
 HMODULE module=nullptr;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&setup),&module)||!GetModuleFileNameW(module,self,32768))return false;
 const auto filename=wcsrchr(self,L'\\');if(!filename||(wcscmp(filename+1,L"ac8_guest_player_stage_r15.dll")&&wcscmp(filename+1,L"ac8_guest_player_stage_r15a.dll")&&wcscmp(filename+1,L"ac8_guest_player_stage_r15b.dll")))return false;
 std::wstring requested=std::wstring(source)+L"\\..\\..\\..\\"+(filename+1);
 if(!GetFullPathNameW(requested.c_str(),32768,expected,nullptr)||_wcsicmp(self,expected))return false;
 if(!GetModuleFileNameW(nullptr,expected,32768))return false;const auto name=wcsrchr(expected,L'\\');if(!name||_wcsicmp(name+1,L"AceCombat8.exe"))return false;
 if(!thread)thread=GetCurrentThreadId();if(thread!=GetCurrentThreadId())return false;base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));output=path;return code();
}
bool number(const std::string&s,uint64_t&v){if(s.empty()||s.size()>20||s[0]=='-'||s[0]=='+')return false;errno=0;char*end=nullptr;v=strtoull(s.c_str(),&end,0);return !errno&&end==s.c_str()+s.size();}
struct Request{uintptr_t world=0,pc=0,host=0,npc=0,unit=0,klass=0,cdo=0;uint32_t pc_pawn=0,pawn_pc=0;};
bool request(Request&r){
 FILE*f=_wfsopen((output+L"\\guest-player-stage-request.tsv").c_str(),L"rb",_SH_DENYNO);if(!f)return false;char buffer[2049]{};auto n=fread(buffer,1,sizeof buffer,f);fclose(f);if(!n||n>2048)return false;
 std::map<std::string,std::string>m;std::string text(buffer,n);size_t at=0;
 while(at<text.size()){auto end=text.find('\n',at);if(end==std::string::npos)return false;auto line=text.substr(at,end-at);at=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos||!m.emplace(line.substr(0,tab),line.substr(tab+1)).second)return false;}
 if(m.size()!=12||m["format"]!="ac8-guest-player-stage-v1")return false;
 uint64_t created=0;auto now=static_cast<uint64_t>(std::time(nullptr));if(!number(m["created_unix"],created)||created>now+1||(created<now&&now-created>3))return false;
 uintptr_t*values[]={&r.world,&r.pc,&r.host,&r.npc,&r.unit,&r.klass,&r.cdo};const char*names[]={"world","controller","host","baxter","unit","class","cdo"};
 for(unsigned i=0;i<7;++i){uint64_t value=0;if(!number(m[names[i]],value)||!pointer(value))return false;*values[i]=value;}
 uint64_t a=0,b=0;if(!number(m["pc_pawn_offset"],a)||!number(m["pawn_pc_offset"],b)||a<40||a>8192||a%8||b<40||b>8192||b%8)return false;
 r.pc_pawn=static_cast<uint32_t>(a);r.pawn_pc=static_cast<uint32_t>(b);return m["slot"]=="1";
}
Request baseline;
bool role_array(uintptr_t offset){uintptr_t data=0;int32_t count=0,cap=0,index=-1,serial=0;
 return read(unit.pointer+offset,data)&&pointer(data)&&read(unit.pointer+offset+8,count)&&count==1&&read(unit.pointer+offset+12,cap)&&cap>=1&&cap<=16&&read(data,index)&&read(data+4,serial)&&index==npc.index&&serial==npc.serial&&serial>0;
}
bool originals(){uintptr_t p=0,c=0,u=0;
 return same(world)&&same(pc)&&same(host)&&same(npc)&&same(unit)&&same(klass)&&same(cdo)&&read(pc.pointer+baseline.pc_pawn,p)&&p==host.pointer&&read(host.pointer+baseline.pawn_pc,c)&&c==pc.pointer&&read(npc.pointer+0xfa0,u)&&u==unit.pointer&&role_array(0x2c0)&&role_array(0x2d0)&&role_array(0x2e0)&&role_array(0x310);
}
bool preflight(const Request&r){
 baseline=r;Identity*ids[]={&world,&pc,&host,&npc,&unit,&klass,&cdo};uintptr_t values[]={r.world,r.pc,r.host,r.npc,r.unit,r.klass,r.cdo};
 for(unsigned i=0;i<7;++i){
  if(!identify(values[i],*ids[i]))return false;
  if(!ids[i]->serial){stabilized_serials|=1u<<i;using Serial=int32_t(__fastcall*)(uintptr_t,int32_t);auto expected=reinterpret_cast<Serial>(base+0x1aae560)(base+0xdc60cd0,ids[i]->index);if(expected<=0||!identify(values[i],*ids[i])||ids[i]->serial!=expected)return false;}
 }
 uintptr_t cl=0,def=0,vt=0,level=0,w=0;uint32_t flags=0;unsigned char type=0;
 if(!read(r.world+0x13a,type)||type!=1||!read(r.world+0x30,level)||!pointer(level)||!read(level+0xc0,w)||w!=r.world||!read(r.klass+0x110,def)||def!=r.cdo||!read(r.cdo+0x10,cl)||cl!=r.klass||!read(r.cdo,vt)||vt!=base+0xcc01cc8||!read(r.cdo+8,flags)||!(flags&0x10))return false;
 return originals()&&r.host!=r.npc;
}
void receipt(uintptr_t actor){++receipts;receipt_seen=true;raw=actor;if(receipts!=1||!identify(actor,owned)){reason="receipt_owned_identity_unverified";quarantine=true;return;}if(!originals()){reason="receipt_original_identity_changed";quarantine=true;return;}
 uintptr_t cl=0;unsigned char begin=0,finish=0;if(!read(actor+0x10,cl)||cl!=klass.pointer||!read(actor+0x5d,begin)||(begin&12)||!read(actor+0x5c,finish)||(finish&9)){reason="receipt_deferred_layout_unverified";quarantine=true;return;}
 *reinterpret_cast<unsigned char*>(actor+0x3f4)=0;*reinterpret_cast<unsigned char*>(actor+0x32)&=static_cast<unsigned char>(~4u);*reinterpret_cast<unsigned char*>(actor+0x33)=0;*reinterpret_cast<unsigned char*>(actor+0x5a)&=static_cast<unsigned char>(~1u);
 *reinterpret_cast<unsigned char*>(actor+0x2a0)=0;*reinterpret_cast<unsigned char*>(actor+0x2a1)=0;
 using Serial=int32_t(__fastcall*)(uintptr_t,int32_t);auto serial=reinterpret_cast<Serial>(base+0x1aae560)(base+0xdc60cd0,owned.index);
 if(serial<=0||!identify(actor,owned)||owned.serial!=serial){quarantine=true;return;}barrier=true;
}
struct Context{bool self=false,matched=false;unsigned calls=0;uintptr_t expected=0;};
struct Storage{uintptr_t*table;Context*context;};
void* __fastcall address(void*p){return static_cast<Storage*>(p)->context;}
void __fastcall invoke(void*p,uintptr_t*actor){auto*c=static_cast<Context*>(p);if(c->self){++c->calls;c->matched=actor&&*actor==c->expected;}else receipt(actor?*actor:0);}
uintptr_t table[3]={0,reinterpret_cast<uintptr_t>(&address),0};
bool selfcheck(){Context c;c.self=true;c.expected=0x12345678;Storage s{table,&c};alignas(16)uintptr_t callable[8]{};callable[0]=reinterpret_cast<uintptr_t>(&invoke);callable[2]=reinterpret_cast<uintptr_t>(&s);using F=void(__fastcall*)(void*,uintptr_t);reinterpret_cast<F>(base+0x4263b80)(callable,c.expected);return c.calls==1&&c.matched;}
bool owned_fenced(){unsigned char active=1,start=4,state=1,allow=1,auto_pc=1,auto_ai=1;uintptr_t controller=1;return barrier&&same(owned)&&read(raw+0x3f4,active)&&!active&&read(raw+0x32,start)&&!(start&4)&&read(raw+0x33,state)&&!state&&read(raw+0x5a,allow)&&!(allow&1)&&read(raw+0x2a0,auto_pc)&&!auto_pc&&read(raw+0x2a1,auto_ai)&&!auto_ai&&read(raw+baseline.pawn_pc,controller)&&!controller;}
void cleanup(){
 if(!attempted||!owned.pointer){reason="no_verified_owned_actor";report("refused");return;}
 if(gone()){retired=true;reason="owned_identity_retired";report("retired");return;}
 uintptr_t entry=0,actual=0;int32_t serial=0;unsigned char pending=0;
 if(item(owned.index,entry)&&read(entry,actual)&&actual==raw&&read(entry+16,serial)&&serial==owned.serial&&read(raw+0x5d,pending)&&(pending&1)){reason="actor_destroy_pending";report("cleanup_pending");return;}
 if(quarantine||!same(owned)||!owned_fenced()||!originals()||destroys>=3){reason="cleanup_identity_or_barrier_unverified";report("quarantine");return;}
 ++destroys;using F=bool(__fastcall*)(uintptr_t,bool);bool ok=reinterpret_cast<F>(base+0x3fe0160)(raw,false);reason=ok?"destroy_requested":"destroy_refused";report("cleanup_pending");
}
void stage(){
 if(attempted){reason="attempt_already_consumed";report("refused");return;}
 Request r;if(!request(r)||!preflight(r)||!selfcheck()){reason="preflight_contract_refused";report("refused");return;}
 attempted=true;reason="spawn_entered";report("creating");
 alignas(16)double transform[12]={0,0,0,1,0,0,0,0,1,1,1,0};
 alignas(16)unsigned char params[128]{};params[0x30]=1;params[0x31]=1;params[0x32]=4;uint32_t flags=8;memcpy(params+0x34,&flags,4);
 Context context;Storage storage{table,&context};auto call=reinterpret_cast<uintptr_t>(&invoke),capture=reinterpret_cast<uintptr_t>(&storage);memcpy(params+0x40,&call,8);memcpy(params+0x50,&capture,8);
 using F=uintptr_t(__fastcall*)(uintptr_t,uintptr_t,const void*,const void*);auto returned=reinterpret_cast<F>(base+0x465a120)(r.world,r.klass,transform,params);
 if(!receipt_seen||returned!=raw||receipts!=1||quarantine||!owned_fenced()||!originals()){if(!quarantine)reason="spawn_outcome_or_barrier_unverified";quarantine=true;report("quarantine");return;}
 FILE*f=_wfsopen((output+L"\\guest-player-stage-constructor.tsv").c_str(),L"w",_SH_DENYWR);
 if(f){unsigned char scalars[72]{};if(bytes(raw+0xf98,scalars,sizeof scalars)){fprintf(f,"selected_scalars_f98\t");for(auto v:scalars)fprintf(f,"%02x",v);fprintf(f,"\n");}for(unsigned off:{0x1328u,0x16a8u,0xed0u,0x3ab0u}){uintptr_t p=0;if(read(raw+off,p))fprintf(f,"pointer_%x\t0x%llx\n",off,static_cast<unsigned long long>(p));}fclose(f);}
 reason="deferred_player_actor_fenced_originals_unchanged";report("staged");
}

void recover(){
 if(attempted||!GetModuleHandleW(L"ac8_guest_player_stage_r15.dll")){reason="recovery_not_available";report("refused");return;}
 FILE*f=_wfsopen((output+L"\\guest-player-stage.tsv").c_str(),L"rb",_SH_DENYNO);if(!f)return;char b[2049]{};auto n=fread(b,1,sizeof b,f);fclose(f);if(!n||n>2048)return;
 std::map<std::string,std::string>m;std::string text(b,n);size_t at=0;
 while(at<text.size()){auto end=text.find('\n',at);if(end==std::string::npos)return;auto line=text.substr(at,end-at);at=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos)return;m[line.substr(0,tab)]=line.substr(tab+1);}
 uint64_t object=0,index=0;if(m["attempted"]!="1"||m["receipts"]!="1"||m["barrier"]!="0"||m["quarantine"]!="1"||m["finish_called"]!="0"||m["ai_mutated"]!="0"||m["role_mutated"]!="0"||!number(m["owned"],object)||!number(m["index"],index)||index>INT32_MAX)return;
 Request r;if(!request(r)||!preflight(r)){reason="recovery_fresh_preflight_refused";report("refused");return;}
 Identity candidate;uintptr_t actual_class=0,vt=0,owner_level=0,owner_world=0,controller=1;unsigned char begin=255,finish=255;
 if(!identify(object,candidate)||candidate.index!=static_cast<int32_t>(index)||object==r.host||object==r.npc||object==r.cdo||!read(object,vt)||vt!=base+0xcc01cc8||!read(object+0x10,actual_class)||actual_class!=r.klass||!read(object+0x20,owner_level)||!pointer(owner_level)||!read(owner_level+0xc0,owner_world)||owner_world!=r.world||!read(object+r.pawn_pc,controller)||controller||!read(object+0x5d,begin)||(begin&13)||!read(object+0x5c,finish)||(finish&9)){
  reason="recovery_owned_constructor_proof_refused";report("refused");return;
 }
 attempted=true;receipt(object);
 if(!quarantine&&owned_fenced()&&originals()){reason="recovery_owned_deferred_actor_fenced";report("staged");cleanup();}
 else {quarantine=true;report("quarantine");}
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_guest_player_stage(void*){if(setup())stage();return 0;}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_guest_player_cleanup(void*){if(setup())cleanup();return 0;}

extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_guest_player_recover(void*){if(setup())recover();return 0;}
