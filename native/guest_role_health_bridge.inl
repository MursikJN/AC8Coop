// Included inside the exact-build probe namespace. Per-instance interface only:
// no engine code patch, no player pointer in an AI array, no extra role actor.
struct RoleHealthBinding {
 uintptr_t original=0,target=0;bool installed=false,consumed=false;
 bool forwarded_only=false;
 std::array<double,3> last_position{};uint8_t last_faction=1;uint64_t last_name=0;
 std::array<uintptr_t,4> original_functions{},target_functions{};
 std::array<unsigned,4> calls{};std::wstring persona;
} role_health;
bool role_health_target(uintptr_t self){
 Backend b;
 return self==role_unit.pointer+0x298&&GetCurrentThreadId()==thread_id&&role_prepared&&same_header(role_unit,true)&&
  ledger.finished_ready&&!ledger.cleanup_requested&&b.own_actor()&&same_header(headers[0],true);
}
bool role_health_original(uintptr_t self){return !role_health.forwarded_only&&self==role_unit.pointer+0x298&&same_header(role_unit,true);}
void __fastcall role_health_location(uintptr_t self,double* out){
 if(role_health_target(self)){++role_health.calls[0];using F=void(__fastcall*)(uintptr_t,double*);reinterpret_cast<F>(role_health.target_functions[0])(ledger.raw_owned+0x320,out);if(out)std::copy(out,out+3,role_health.last_position.begin());}
 else if(role_health_original(self)){using F=void(__fastcall*)(uintptr_t,double*);reinterpret_cast<F>(role_health.original_functions[0])(self,out);}
 else if(out)std::copy(role_health.last_position.begin(),role_health.last_position.end(),out);
}
uint8_t __fastcall role_health_faction(uintptr_t self){
 if(role_health_target(self)){++role_health.calls[1];using F=uint8_t(__fastcall*)(uintptr_t);role_health.last_faction=reinterpret_cast<F>(role_health.target_functions[1])(ledger.raw_owned+0x320);return role_health.last_faction;}
 if(role_health_original(self)){using F=uint8_t(__fastcall*)(uintptr_t);return reinterpret_cast<F>(role_health.original_functions[1])(self);}return role_health.last_faction;
}
float __fastcall role_health_rate(uintptr_t self){
 if(role_health_target(self)){++role_health.calls[2];using F=float(__fastcall*)(uintptr_t);return reinterpret_cast<F>(role_health.target_functions[2])(ledger.raw_owned+0x320);}
 if(role_health_original(self)){using F=float(__fastcall*)(uintptr_t);return reinterpret_cast<F>(role_health.original_functions[2])(self);}return 0;
}
uint64_t* __fastcall role_health_name(uintptr_t self,uint64_t* out){
 if(role_health_target(self)){++role_health.calls[3];using F=uint64_t*(__fastcall*)(uintptr_t,uint64_t*);auto result=reinterpret_cast<F>(role_health.target_functions[3])(ledger.raw_owned+0x320,out);if(result)role_health.last_name=*result;return result;}
 if(role_health_original(self)){using F=uint64_t*(__fastcall*)(uintptr_t,uint64_t*);return reinterpret_cast<F>(role_health.original_functions[3])(self,out);}if(out)*out=role_health.last_name;return out;
}
const std::array<uintptr_t,4> role_health_table={reinterpret_cast<uintptr_t>(&role_health_location),reinterpret_cast<uintptr_t>(&role_health_faction),reinterpret_cast<uintptr_t>(&role_health_rate),reinterpret_cast<uintptr_t>(&role_health_name)};
bool role_health_restore(){
 if(!role_health.installed)return true;
 if(role_health.forwarded_only)return false;
 if(!same_header(role_unit,true))return false;
 auto slot=reinterpret_cast<void* volatile*>(role_unit.pointer+0x298);
 const auto previous=InterlockedCompareExchangePointer(slot,reinterpret_cast<void*>(role_health.original),const_cast<uintptr_t*>(role_health_table.data()));
 uintptr_t actual=0;
 if(previous!=role_health_table.data()||!read(role_unit.pointer+0x298,actual)||actual!=role_health.original)return false;
 role_health.installed=false;return true;
}
bool role_string(uintptr_t address,std::wstring& out){
 uintptr_t data=0;int32_t count=0,capacity=0;
 if(!read(address,data)||!read(address+8,count)||!read(address+12,capacity)||count<0||count>256||capacity<count||capacity>4096)return false;
 if(!count){out.clear();return true;}
 std::array<wchar_t,256> chars{};if(!guarded_read(data,chars.data(),count*sizeof(wchar_t))||chars[count-1])return false;
 out.assign(chars.data(),static_cast<size_t>(count-1));return true;
}
bool role_persona(){
 std::string text;uint64_t peer=0;if(!read_file(L"guest-role-peer.txt",text))return diagnostic_fail("steam_peer_not_configured");
 while(!text.empty()&&(text.back()=='\r'||text.back()=='\n'))text.pop_back();
 if(text.size()!=17||!parse_number(text,peer,10)||((peer>>56)!=1)||((peer>>52)&15)!=1)return diagnostic_fail("steam_peer_invalid");
 HMODULE steam=GetModuleHandleW(L"steam_api64.dll");if(!steam)return diagnostic_fail("steam_api_unavailable");
 using Access=void*(__cdecl*)();using GetName=const char*(__cdecl*)(void*,uint64_t);using Request=bool(__cdecl*)(void*,uint64_t,bool);
 auto access=reinterpret_cast<Access>(GetProcAddress(steam,"SteamAPI_SteamFriends_v017"));
 auto get=reinterpret_cast<GetName>(GetProcAddress(steam,"SteamAPI_ISteamFriends_GetFriendPersonaName"));
 auto request_name=reinterpret_cast<Request>(GetProcAddress(steam,"SteamAPI_ISteamFriends_RequestUserInformation"));
 if(!access||!get||!request_name)return diagnostic_fail("steam_friends_exports_unavailable");
 auto friends=access();if(!friends)return diagnostic_fail("steam_friends_interface_unavailable");
 const char* name=get(friends,peer);std::string copy;char ch=0;
 for(unsigned i=0;i<512;++i){if(!guarded_read(reinterpret_cast<uintptr_t>(name)+i,&ch,1))return diagnostic_fail("steam_name_unreadable");if(!ch)break;copy.push_back(ch);}
 if(ch)return diagnostic_fail("steam_name_too_long");
 if(copy.empty()||copy=="[unknown]"){request_name(friends,peer,true);return diagnostic_fail("steam_name_pending");}
 const int length=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,copy.c_str(),static_cast<int>(copy.size()),nullptr,0);
 if(length<1||length>128)return diagnostic_fail("steam_name_encoding_invalid");
 role_health.persona.resize(length);if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,copy.c_str(),static_cast<int>(copy.size()),role_health.persona.data(),length)!=length)return false;
 for(auto& c:role_health.persona)if(c<32)c=L' ';
 return true;
}
bool role_name_apply(){
 if(!role_persona())return false;
 Backend b;if(!role_prepared||!b.finished_graph()||!same_header(role_npc,true)||!same_header(role_unit,true))return diagnostic_fail("name_role_graph_changed");
 const uintptr_t rvas[]={0x16dfea0,0x7c97dd0,0x7c98080};
 const unsigned char expected[][16]={
  {0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b,0xd9,0x48,0x3b,0xca,0x74,0x5d,0x44,0x8b},
  {0x48,0x89,0x5c,0x24,0x18,0x48,0x89,0x6c,0x24,0x20,0x57,0x48,0x83,0xec,0x60,0x83},
  {0x48,0x89,0x5c,0x24,0x18,0x48,0x89,0x6c,0x24,0x20,0x57,0x48,0x83,0xec,0x60,0x83}};
 unsigned char actual[16];for(unsigned i=0;i<3;++i)if(!guarded_read(image_base+rvas[i],actual,16)||std::memcmp(actual,expected[i],16))return diagnostic_fail("name_native_fingerprint_mismatch");
 using Copy=uintptr_t(__fastcall*)(uintptr_t,uintptr_t);
 for(unsigned offset:{0x428u,0x438u}){
  std::wstring source;if(!role_string(role_npc.pointer+offset,source)||source.empty())return diagnostic_fail("source_role_string_invalid");
  reinterpret_cast<Copy>(image_base+0x16dfea0)(ledger.raw_owned+offset,role_npc.pointer+offset);
  std::wstring own,after;if(!role_string(ledger.raw_owned+offset,own)||!role_string(role_npc.pointer+offset,after)||own!=source||after!=source)return diagnostic_fail("role_string_copy_unverified");
 }
 uint8_t faction=0;if(!read(role_npc.pointer+0x3b2,faction)||!b.write(ledger.raw_owned+0x3b2,&faction,1))return diagnostic_fail("guest_faction_copy_failed");
 struct StringView{const wchar_t* data;int32_t count,capacity;};const int32_t n=static_cast<int32_t>(role_health.persona.size()+1);
 const StringView view{role_health.persona.c_str(),n,n};using Set=void(__fastcall*)(uintptr_t,const StringView*);
 reinterpret_cast<Set>(image_base+0x7c97dd0)(ledger.raw_owned,&view);
 reinterpret_cast<Set>(image_base+0x7c98080)(ledger.raw_owned,&view);
 std::wstring a,c;if(!role_string(ledger.raw_owned+0x6d8,a)||!role_string(ledger.raw_owned+0x6e8,c)||a!=role_health.persona||c!=role_health.persona)return diagnostic_fail("steam_name_cache_readback_failed");
 return true;
}
struct HealthSample{std::array<double,3> position{};uint8_t faction=0;float rate=0;uint64_t name=0;};
HealthSample health_sample(uintptr_t self,const std::array<uintptr_t,4>& table){
 HealthSample s;using Location=void(__fastcall*)(uintptr_t,double*);using Faction=uint8_t(__fastcall*)(uintptr_t);using Rate=float(__fastcall*)(uintptr_t);using Name=uint64_t*(__fastcall*)(uintptr_t,uint64_t*);
 reinterpret_cast<Location>(table[0])(self,s.position.data());s.faction=reinterpret_cast<Faction>(table[1])(self);s.rate=reinterpret_cast<Rate>(table[2])(self);reinterpret_cast<Name>(table[3])(self,&s.name);return s;
}
bool role_health_trial(){
 if(role_health.consumed)return diagnostic_fail("role_interface_trial_already_consumed");
 Backend b;if(!role_prepared||!b.finished_graph()||!model_report.models_seeded||!same_header(role_unit,true)||!same_header(role_npc,true))return diagnostic_fail("role_interface_prerequisite_failed");
 if(!role_name_apply())return false;
 if(!read(role_unit.pointer+0x298,role_health.original)||role_health.original!=image_base+0xcb22e20||!read(ledger.raw_owned+0x320,role_health.target)||role_health.target!=image_base+0xcc01c10||
  !guarded_read(role_health.original,role_health.original_functions.data(),32)||!guarded_read(role_health.target,role_health.target_functions.data(),32))return diagnostic_fail("health_interface_vtable_unverified");
 const uintptr_t u[]={0x7dcec60,0x7dcf3a0,0x7dcf3c0,0x7dceb50},p[]={0x7d1c7a0,0x7d1c810,0x7d1c820,0x7d1c760};
 for(unsigned i=0;i<4;++i)if(role_health.original_functions[i]!=image_base+u[i]||role_health.target_functions[i]!=image_base+p[i])return diagnostic_fail("health_interface_function_unverified");
 if(!b.pose_and_final_barrier())return false;
 const auto source_before=health_sample(role_unit.pointer+0x298,role_health.original_functions);
 const auto target=health_sample(ledger.raw_owned+0x320,role_health.target_functions);
 auto slot=reinterpret_cast<void* volatile*>(role_unit.pointer+0x298);
 role_health.consumed=true;
 if(InterlockedCompareExchangePointer(slot,const_cast<uintptr_t*>(role_health_table.data()),reinterpret_cast<void*>(role_health.original))!=reinterpret_cast<void*>(role_health.original))return diagnostic_fail("health_interface_swap_raced");
 role_health.installed=true;
 const auto routed=health_sample(role_unit.pointer+0x298,role_health_table);
 const bool matched=target.position==routed.position&&target.faction==routed.faction&&std::isfinite(target.rate)&&target.rate==routed.rate&&target.name==routed.name;
 const bool restored=role_health_restore();
 const auto after=restored?health_sample(role_unit.pointer+0x298,role_health.original_functions):HealthSample{};
 const bool preserved=restored&&after.position==source_before.position&&after.faction==source_before.faction&&after.rate==source_before.rate&&after.name==source_before.name;
 const auto path=directory+L"\\guest-role-health-"+AC8_GUEST_REV_W+L".tsv";FILE* f=nullptr;
 if(!_wfopen_s(&f,path.c_str(),L"wb")&&f){std::fprintf(f,"routed_to_player\t%d\noriginal_unit_restored\t%d\nsource_unit_preserved\t%d\nlocation_calls\t%u\nfaction_calls\t%u\nhealth_calls\t%u\nname_calls\t%u\nsteam_persona_cached\t1\nnpc_removed\t0\nengine_role_committed\t0\n",matched?1:0,restored?1:0,preserved?1:0,role_health.calls[0],role_health.calls[1],role_health.calls[2],role_health.calls[3]);std::fclose(f);}
 native_failure=matched&&restored&&preserved?"unit_health_location_name_forwarded_and_restored":"unit_interface_trial_readback_failed";
 return matched&&restored&&preserved;
}
