// Exact-build native command bridge. Each fresh request can confirm once.
// No synthetic OS input, level travel bypass, game object allocation or direct save-file writes.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <ctime>
#include <map>
#include <string>
#include <cerrno>
#include <share.h>
#include <set>
#include "menu_route_contract.h"
namespace {
uintptr_t base=0;DWORD game_thread=0;std::wstring output;std::string consumed;
std::set<std::string>used_requests,used_actions;
bool read_bytes(uintptr_t p,void*out,size_t n){
 if(p<0x10000||p>=0x800000000000ULL||!n||n>4096||p+n>=0x800000000000ULL)return false;
 __try{memcpy(out,reinterpret_cast<void*>(p),n);return true;}
 __except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
template<class T>bool read(uintptr_t p,T&v){return read_bytes(p,&v,sizeof v);}
bool ptr(uintptr_t p){return p>=0x10000&&p<0x800000000000ULL&&p%8==0;}
bool env(const wchar_t*key,wchar_t*out,DWORD n){const auto size=GetEnvironmentVariableW(key,out,n);return size>0&&size<n;}
bool setup(){
 wchar_t marker[32]{},path[32768]{},self[32768]{},source[32768]{},normalized[32768]{};
 if(!env(L"AC8_COOP_RECON",marker,32)||wcscmp(marker,L"1")||!env(L"AC8_COOP_RECON_OUTPUT",path,32768)||!env(L"AC8_COOP_RECON_EXTENSION",source,32768))return false;
 HMODULE module=nullptr;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&setup),&module))return false;
 if(!GetModuleFileNameW(module,self,32768))return false;
 auto last=wcsrchr(source,L'\\');if(!last)return false;*last=0;
 const auto filename=wcsrchr(self,L'\\');if(!filename||(wcsncmp(filename+1,L"ac8_menu_route_r9",17)&&wcsncmp(filename+1,L"ac8_menu_route_r13",18))||!wcsstr(filename+1,L".dll"))return false;
 std::wstring expected=std::wstring(source)+L"\\..\\..\\..\\"+(filename+1);
 if(!GetFullPathNameW(expected.c_str(),32768,normalized,nullptr)||_wcsicmp(self,normalized))return false;
 if(!GetModuleFileNameW(nullptr,source,32768)||(last=wcsrchr(source,L'\\'))==nullptr||_wcsicmp(last+1,L"AceCombat8.exe"))return false;
 if(!game_thread)game_thread=GetCurrentThreadId();if(game_thread!=GetCurrentThreadId())return false;
 base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));output=path;return true;
}
void status(const char*state,const char*reason,const std::string&stamp,int selected=-1,int value=-1,int count=0,bool returned=false){
 const auto temp=output+L"\\menu-route-status.tmp",path=output+L"\\menu-route-status.tsv";FILE*f=_wfsopen(temp.c_str(),L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"format\tac8-menu-route-v1\nstatus\t%s\nreason\t%s\nstamp\t%s\nselected\t%d\nvalue\t%d\ncount\t%d\nreturned\t%d\n",state,reason,stamp.c_str(),selected,value,count,returned?1:0);fclose(f);MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
bool number(const std::string&s,uint64_t&out){if(s.empty()||s.size()>20||s[0]=='-'||s[0]=='+')return false;char*end=nullptr;errno=0;out=strtoull(s.c_str(),&end,0);return !errno&&end==s.c_str()+s.size();}
bool identity(uintptr_t object,std::array<unsigned char,40>&header,int32_t&serial,bool allow_zero_serial=false){
 if(!ptr(object)||!read_bytes(object,header.data(),40))return false;int32_t index=-1,count=0,chunks=0;uintptr_t array=0,chunk=0,actual=0;
 memcpy(&index,header.data()+12,4);uint32_t flags=0;memcpy(&flags,header.data()+8,4);if(flags&0x60000010)return false;
 if(index<0||!read(base+0xdc60cd0+0x24,count)||index>=count||count>0x1000000||!read(base+0xdc60cd0+0x2c,chunks)||chunks<=0||chunks>4096||index/65536>=chunks||!read(base+0xdc60cd0+0x10,array)||!ptr(array)||!read(array+static_cast<uintptr_t>(index/65536)*8,chunk)||!ptr(chunk))return false;
 auto item=chunk+static_cast<uintptr_t>(index&65535)*0x18;
 return read(item,actual)&&actual==object&&read(item+0x10,serial)&&(serial>0||(allow_zero_serial&&serial==0));
}
bool command_text(uintptr_t address,std::string&out){
 uintptr_t data=0;int32_t count=0,capacity=0;if(!read(address,data)||!read(address+8,count)||!read(address+12,capacity)||count<0||count>128||capacity<count||capacity>512)return false;
 if(!count){out.clear();return true;}std::array<wchar_t,128>text{};
 if(!ptr(data)||!read_bytes(data,text.data(),static_cast<size_t>(count)*2)||text[static_cast<size_t>(count)-1])return false;
 out.clear();for(int32_t i=0;i<count-1;++i){if(text[static_cast<size_t>(i)]<32||text[static_cast<size_t>(i)]>126)return false;out.push_back(static_cast<char>(text[static_cast<size_t>(i)]));}return true;
}
bool known_table(uintptr_t rva){return rva==0xc82cf38||rva==0xc7f05b0||rva==0xc7f6630||rva==0xc7f5c20||rva==0xc80f698||rva==0xc81d2b0||rva==0xc8109e8||rva==0xc811bd0||rva==0xc815438||rva==0xc815d90;}
void inventory(uintptr_t object,const std::string&stamp){
 std::array<unsigned char,40>head{};int32_t serial=0,count=0,cap=0;uintptr_t table=0,array=0;int16_t selected=-1;unsigned char visibility=0,state=0;
 if(!identity(object,head,serial)||!read(object,table)||!known_table(table-base)||!read(object+0x690,array)||!ptr(array)||!read(object+0x698,count)||!read(object+0x69c,cap)||count<=0||count>128||cap<count||cap>256||!read(object+0x688,selected)||!read(object+0xdc,visibility)||!read(object+0x3cc,state)){status("refused","inventory_contract",stamp);return;}
 FILE*f=_wfsopen((output+L"\\menu-route-commands.tsv").c_str(),L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"stamp\t%s\nvtable_rva\t0x%llx\nselected\t%d\nvisibility\t%u\nstate\t%u\n",stamp.c_str(),static_cast<unsigned long long>(table-base),selected,visibility,state);
 if(table-base==0xc81d2b0){unsigned char slot=255;if(read(object+0x73b,slot))fprintf(f,"aircraft_edit_slot\t%u\n",slot);}
 bool ok=true;
 for(int32_t i=0;i<count;++i){const auto entry=array+static_cast<uintptr_t>(i)*0x1b8;std::string tag,caption;int32_t a=0,b=0,mission=-1;unsigned char weapon=0;
  if(!command_text(entry+0xf8,tag)||!command_text(entry+0x130,caption)||!read(entry+0x108,a)||!read(entry+0x158,b)||!read(entry+0x154,mission)||!read(entry+0x160,weapon)){ok=false;break;}
  fprintf(f,"command\t%d\t%s\t%s\t%d\t%d\t%u\t%d\n",i,tag.c_str(),caption.c_str(),a,b,weapon,mission);
 }
 fclose(f);status(ok?"verified":"refused",ok?"inventory_complete":"command_text_invalid",stamp,selected,-1,count);
}
bool map_plane(uintptr_t map,unsigned slot,int&aircraft){
 uintptr_t data=0,hash=0;int32_t count=0,capacity=0,free=0,buckets=0,index=-1;
 if(!read(map+0x10,data)||!ptr(data)||!read(map+0x18,count)||count<1||count>16||!read(map+0x1c,capacity)||capacity<count||capacity>32||!read(map+0x44,free)||free<0||free>count||!read(map+0x58,buckets)||buckets<1||buckets>32||(buckets&(buckets-1))||!read(map+0x50,hash))return false;
 if(!hash)hash=map+0x48;if(!ptr(hash)||!read(hash+(slot&static_cast<unsigned>(buckets-1))*4,index))return false;
 for(int seen=0;seen<count&&index>=0&&index<count;++seen){unsigned char key=255;const auto entry=data+static_cast<uintptr_t>(index)*0x50;
  if(!read(entry,key))return false;if(key==slot)return read(entry+8,aircraft);if(!read(entry+0x48,index))return false;
 }return false;
}
void hangar_loadout(uintptr_t object,const std::string&stamp){
 std::array<unsigned char,40>head{};int32_t serial=0;uintptr_t table=0;unsigned char visibility=0,state=0;unsigned char bytes[16]{};
 if(!identity(object,head,serial)||!read(object,table)||!known_table(table-base)||table-base<0xc800000||!read(object+0xdc,visibility)||visibility!=0||!read(object+0x3cc,state)||state!=5||!read_bytes(base+0x7a681e0,bytes,16)||!ac8route::fingerprint(bytes,"4883ec28e8e72e47004885c074754889")){status("refused","hangar_loadout_contract",stamp);return;}
 // Stock read-only menu subsystem getter, verified in the selected-aircraft handler.
 uintptr_t data=reinterpret_cast<uintptr_t(__fastcall*)(uintptr_t)>(base+0x7a681e0)(object);
 std::array<unsigned char,40>data_head{};int32_t data_serial=0;int player=-1,guest=-1;
 const bool data_identity=identity(data,data_head,data_serial,true);
 FILE*debug=_wfsopen((output+L"\\hangar-map-diagnostic.tsv").c_str(),L"w",_SH_DENYWR);
 if(debug){fprintf(debug,"data\t0x%llx\nidentity\t%d\n",static_cast<unsigned long long>(data),data_identity?1:0);
  for(auto offset:{0u,0x1b0u,0x220u}){unsigned char raw[112]{};if(read_bytes(data+offset,raw,sizeof(raw))){fprintf(debug,"raw_%x\t",offset);for(auto byte:raw)fprintf(debug,"%02x",byte);fprintf(debug,"\n");}}
  fclose(debug);
 }
 if(!data_identity||!map_plane(data+0x1b0,0,player)||!map_plane(data+0x1b0,1,guest)){status("refused","hangar_plane_map",stamp);return;}
 status("verified","hangar_plane_map",stamp,player,guest,2);
}
void dispatch(){
 if(!setup())return;
 FILE*f=_wfsopen((output+L"\\menu-route-request.tsv").c_str(),L"rb",_SH_DENYNO);if(!f){status("refused","missing_request","");return;}
 char b[1025]{};const auto n=fread(b,1,1025,f);fclose(f);if(!n||n>1024){status("refused","request_size","");return;}
 std::string text(b,n);std::map<std::string,std::string>fields;size_t pos=0;
 while(pos<text.size()){
  auto end=text.find('\n',pos);if(end==std::string::npos){status("refused","request_line","");return;}
  auto line=text.substr(pos,end-pos);pos=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');
  if(tab==std::string::npos||!fields.emplace(line.substr(0,tab),line.substr(tab+1)).second){status("refused","request_fields","");return;}
 }
 const char*names[]={"format","stamp","created_unix","object","operation","kind"};
 if(fields.size()!=6){status("refused","request_fields","");return;}for(auto name:names)if(!fields.count(name)){status("refused","request_fields","");return;}
 const auto stamp=fields["stamp"];if(stamp.empty()||stamp.size()>64||stamp.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")!=std::string::npos){status("refused","stamp","");return;}
 uint64_t created=0,object=0;const auto now=static_cast<uint64_t>(time(nullptr));
 if(fields["format"]!="ac8-menu-route-v1"||!number(fields["object"],object)||!number(fields["created_unix"],created)||created>now||now-created>3||(fields["operation"]!="inspect"&&fields["operation"]!="confirm"&&fields["operation"]!="select")){status("refused","request_contract",stamp);return;}
 if(fields["kind"]=="inventory"&&fields["operation"]=="inspect"){inventory(object,stamp);return;}
 if(fields["kind"]=="hangar_loadout"&&fields["operation"]=="inspect"){hangar_loadout(object,stamp);return;}
 const auto target=ac8route::target(fields["kind"]);
 if(!target.table){status("refused","unknown_kind",stamp);return;}
 std::array<unsigned char,40>head{};int32_t serial=0;uintptr_t vtable=0,confirm=0,commands=0;int16_t selected=-1;int32_t count=0,cap=0;unsigned char visibility=0,state=0;int32_t value=-1;
 if(!identity(object,head,serial)||!read(object,vtable)||vtable!=base+target.table||!read(vtable+238*8,confirm)||confirm!=base+target.confirm||!read(object+0xdc,visibility)||visibility!=0||!read(object+0x3cc,state)||state!=5||!read(object+0x688,selected)||!read(object+0x690,commands)||!ptr(commands)||!read(object+0x698,count)||!read(object+0x69c,cap)||count<=0||count>128||cap<count||cap>256||selected<0||selected>=count){status("refused","widget_or_selection_contract",stamp,selected,value,count);return;}
 if(target.edit_slot>=0){unsigned char slot=255;if(!read(object+0x73b,slot)||slot!=target.edit_slot){status("refused","aircraft_edit_slot",stamp,selected,slot,count);return;}}
 int wanted=-1;
 for(int i=0;i<count;++i){const auto entry=commands+static_cast<uintptr_t>(i)*0x1b8;std::string tag;int aircraft=-1,mission=-1;unsigned char weapon=0;
  if(!command_text(entry+(target.caption?0x130:0xf8),tag)||!read(entry+0x158,aircraft)||!read(entry+0x154,mission)||!read(entry+0x160,weapon)){status("refused","command_data_invalid",stamp);return;}
  if(ac8route::matches(target,tag,aircraft,weapon,count,i,mission)){if(wanted>=0){status("refused","ambiguous_target",stamp);return;}wanted=i;value=target.mission>=0?mission:aircraft;}
 }
 if(wanted<0){status("refused","target_missing",stamp,selected,value,count);return;}
 unsigned char actual[16]{};
 if(!read_bytes(confirm,actual,sizeof actual)||!ac8route::fingerprint(actual,target.fingerprint)){status("refused","confirm_fingerprint",stamp,selected,value,count);return;}
 if(fields["operation"]=="inspect"){status("verified",selected==wanted?"target_selected":"target_available",stamp,selected,value,count);return;}
 const auto action_key=std::to_string(object)+"/"+std::to_string(serial)+"/"+fields["kind"]+"/"+fields["operation"];
 if(used_requests.count(stamp)||used_actions.count(action_key)||used_requests.size()>=128){status("refused","request_or_action_consumed",stamp,selected,value,count);return;}
 std::array<unsigned char,40>again{};int32_t serial_again=0;
 if(!identity(object,again,serial_again)||serial_again!=serial||head!=again){status("refused","identity_changed",stamp);return;}
 if(fields["operation"]=="confirm"&&selected!=wanted){status("refused","target_not_selected",stamp,selected,value,count);return;}
 if(fields["operation"]=="select"){
  if(!read_bytes(base+0x7a8c2a0,actual,sizeof actual)||!ac8route::fingerprint(actual,"40534883ec20488bd90fbf8988060000")){status("refused","focus_fingerprint",stamp);return;}
 }
 if(fields["operation"]=="confirm"&&target.continuation){
  if(!read_bytes(base+target.continuation,actual,sizeof actual)||!ac8route::fingerprint(actual,target.continuation_fingerprint)){status("refused","continuation_fingerprint",stamp);return;}
 }
 consumed=stamp;used_requests.insert(stamp);used_actions.insert(action_key);status("calling",fields["operation"]=="select"?"native_select_once":"native_confirm_once",stamp,selected,value,count);
 if(fields["operation"]=="select"){
  const bool changed=reinterpret_cast<bool(__fastcall*)(uintptr_t,int16_t)>(base+0x7a8c2a0)(object,static_cast<int16_t>(wanted));
  int16_t after=-1;read(object+0x688,after);status(after==wanted?"selected":"refused",after==wanted?"native_target_selected":"selection_failed",stamp,after,value,count,changed);return;
 }
 // A mutation fault is not caught or retried. This is the same current-selection handler.
 bool result=true;
 // The fixed lobby difficulty uses the stock post-dialog continuation. Do not
 // change the user's global collision-assistance preference as a side effect.
 if(target.continuation)reinterpret_cast<void(__fastcall*)(uintptr_t)>(base+target.continuation)(object);
 else result=reinterpret_cast<bool(__fastcall*)(uintptr_t)>(confirm)(object);
 status("returned","native_confirm_returned",stamp,selected,value,count,result);
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_menu_route(void*){dispatch();return 0;}
