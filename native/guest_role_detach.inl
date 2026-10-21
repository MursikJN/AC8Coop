// Bounded reversible detachment proof. The later retirement operation must be
// separate: this trial never calls DestroyActor on an existing mission object.
struct RoleWeakArray {
 uintptr_t address=0,data=0;int32_t count=0,capacity=0;
 std::array<uint64_t,16> values{};unsigned remove=0;
};
bool role_array_capture(uintptr_t at,RoleWeakArray& a){
 a={};a.address=at;
 return read(at,a.data)&&read(at+8,a.count)&&read(at+12,a.capacity)&&a.count>=0&&a.count<=16&&a.capacity>=a.count&&a.capacity<=4096&&
  (!a.count||(pointer(a.data)&&guarded_read(a.data,a.values.data(),a.count*8)));
}
bool role_array_same(const RoleWeakArray&a){
 RoleWeakArray now;return role_array_capture(a.address,now)&&a.data==now.data&&a.count==now.count&&a.capacity==now.capacity&&a.values==now.values;
}
uint64_t role_weak(const Header&h){return uint64_t(uint32_t(h.index))|(uint64_t(uint32_t(h.serial))<<32);}
struct RoleComponentSnapshot {
 Header identity;uintptr_t setter=0,getter=0;plane_component_ticks::Kind kind=plane_component_ticks::Kind::unknown;
 plane_component_ticks::State state{};bool changed=false,base_changed=false;
};
struct RoleDetachState {
 Header manager;std::array<RoleWeakArray,6> unit_arrays{};std::array<RoleWeakArray,2> manager_arrays{};
 std::vector<RoleComponentSnapshot> components;
 uint8_t active=0;bool unit_tick=false,npc_tick=false,mutated=false;
 uintptr_t unit_set=0,unit_get=0,npc_set=0,npc_get=0;
} role_detach;
bool role_detach_guard(){
 Backend b;return role_prepared&&same_header(role_unit,true)&&same_header(role_npc,true)&&same_header(role_detach.manager,true)&&
  b.finished_graph()&&verify_baseline(baseline,false);
}
bool role_component_read(const RoleComponentSnapshot& c,plane_component_ticks::State&s){
 uintptr_t owner=0,vt=0,set=0,get=0;
 if(!same_header(c.identity,false)||!read(c.identity.pointer+0x90,owner)||owner!=role_npc.pointer||!read(c.identity.pointer,vt)||
  !read(vt+0x3d8,set)||set!=c.setter||!read(vt+0x3e8,get)||get!=c.getter||!read(c.identity.pointer+0x3b,s.base_tick))return false;
 if(c.kind==plane_component_ticks::Kind::live&&!read(c.identity.pointer+0xd3,s.custom_enabled))return false;
 if(c.kind==plane_component_ticks::Kind::mesh){if(!read(c.identity.pointer+0xbd0,s.aux_registration))return false;if(s.aux_registration&&(!pointer(s.aux_registration)||!read(s.aux_registration,s.aux_flags)))return false;}
 return true;
}
bool role_components_capture(){
 Backend b;const uintptr_t set=role_npc.pointer+0x218;
 std::array<uint8_t,0x38> before{},after{};if(!guarded_read(set,before.data(),before.size()))return false;
 uintptr_t data=0,external=0;int32_t n=0,cap=0,bits=0,maxbits=0,free=0;
 std::memcpy(&data,before.data(),8);std::memcpy(&n,before.data()+8,4);std::memcpy(&cap,before.data()+12,4);std::memcpy(&external,before.data()+0x20,8);
 std::memcpy(&bits,before.data()+0x28,4);std::memcpy(&maxbits,before.data()+0x2c,4);std::memcpy(&free,before.data()+0x34,4);
 if(n<1||n>512||bits!=n||cap<n||cap>4096||free<0||free>n||maxbits<bits||maxbits>4096||(!external&&bits>128)||!pointer(data))return false;
 auto bitmap=external?external:set+0x10;role_detach.components.clear();unsigned allocated=0;
 for(int i=0;i<bits;++i){uint32_t word=0;if(!read(bitmap+uintptr_t(i/32)*4,word))return false;if(!(word&(1u<<(i%32))))continue;++allocated;
  uintptr_t p=0,vt=0;RoleComponentSnapshot c;
  if(!read(data+uintptr_t(i)*16,p)||!b.component_is_a(p)||!capture_header(p,c.identity,true)||!read(p,vt)||!read(vt+0x3d8,c.setter)||!read(vt+0x3e8,c.getter)||c.setter<image_base||c.getter<image_base)return false;
  c.kind=plane_component_ticks::classify({c.setter-image_base,c.getter-image_base});
  if(c.kind==plane_component_ticks::Kind::unknown||!role_component_read(c,c.state))return false;
  role_detach.components.push_back(c);
 }
 return allocated==static_cast<unsigned>(n-free)&&guarded_read(set,after.data(),after.size())&&before==after;
}
bool role_detach_capture(){
 std::string text;uint64_t p=0;
 if(!read_file(L"guest-role-manager.txt",text))return diagnostic_fail("role_manager_request_absent");
 while(!text.empty()&&(text.back()=='\r'||text.back()=='\n'))text.pop_back();
 if(!parse_number(text,p,0)||!capture_header(p,role_detach.manager,true))return diagnostic_fail("role_manager_identity_invalid");
 uintptr_t vt=0,outer=0,link=0;int32_t holds=-1;
 if(!read(p,vt)||vt!=image_base+0xcb259e0||!read(p+0x20,outer)||outer!=baseline.world||!read(p+0xa8+8,holds)||holds||!read(role_npc.pointer+0xfa0,link)||link!=role_unit.pointer||!role_detach_guard())return diagnostic_fail("role_manager_or_unit_changed");
 const unsigned offsets[]={0x2c0,0x2d0,0x2e0,0x2f0,0x300,0x310};
 for(unsigned i=0;i<6;++i){auto&a=role_detach.unit_arrays[i];if(!role_array_capture(role_unit.pointer+offsets[i],a)||a.count!=1||a.values[0]!=role_weak(role_npc))return diagnostic_fail("role_unit_array_not_singleton");}
 for(unsigned i=0;i<2;++i){auto&a=role_detach.manager_arrays[i];const auto wanted=role_weak(i?role_unit:role_npc);unsigned matches=0;
  if(!role_array_capture(p+(i?0x80:0x70),a)||a.count!=3)return diagnostic_fail("role_manager_count_not_three");
  for(int k=0;k<a.count;++k)if(a.values[k]==wanted){++matches;a.remove=unsigned(k);}
  if(matches!=1)return diagnostic_fail("role_manager_assignment_not_unique");
 }
 uintptr_t uvt=0,nvt=0;
 if(!read(role_unit.pointer,uvt)||!read(uvt+0x480,role_detach.unit_set)||role_detach.unit_set!=image_base+0x7dca3c0||!read(uvt+0x488,role_detach.unit_get)||role_detach.unit_get!=image_base+0x7dca410||
  !read(role_npc.pointer,nvt)||!read(nvt+0x480,role_detach.npc_set)||role_detach.npc_set!=image_base+0x7c8f270||!read(nvt+0x488,role_detach.npc_get)||role_detach.npc_get!=image_base+0x7c8f2c0||!read(role_npc.pointer+0x3f4,role_detach.active)||role_detach.active!=1)return diagnostic_fail("role_tick_dispatch_unverified");
 const unsigned char setter[]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0xf6,0x41,0x32,0x02,0x0f,0xb6};
 const unsigned char unit_get[]={0x80,0xb9,0x06,0x04,0,0,0,0x0f,0x94,0xc0,0xc3},npc_get[]={0x80,0xb9,0xd9,0x25,0,0,0,0x0f,0x94,0xc0,0xc3};unsigned char got[16];
 if(!guarded_read(role_detach.unit_set,got,16)||std::memcmp(got,setter,16)||!guarded_read(role_detach.npc_set,got,16)||std::memcmp(got,setter,16)||
  !guarded_read(role_detach.unit_get,got,sizeof unit_get)||std::memcmp(got,unit_get,sizeof unit_get)||!guarded_read(role_detach.npc_get,got,sizeof npc_get)||std::memcmp(got,npc_get,sizeof npc_get))return diagnostic_fail("role_tick_entry_fingerprint_mismatch");
 using Get=bool(__fastcall*)(uintptr_t);role_detach.unit_tick=reinterpret_cast<Get>(role_detach.unit_get)(role_unit.pointer);role_detach.npc_tick=reinterpret_cast<Get>(role_detach.npc_get)(role_npc.pointer);
 return role_components_capture()?true:diagnostic_fail("role_component_graph_unverified");
}
bool role_components_disable(){
 for(auto& c:role_detach.components){
  plane_component_ticks::State before;if(!role_detach_guard()||!role_component_read(c,before))return false;
  using Set=void(__fastcall*)(uintptr_t,bool);c.changed=true;reinterpret_cast<Set>(c.setter)(c.identity.pointer,false);
  plane_component_ticks::State now;if(!role_component_read(c,now))return false;
  // Live's override controls d3 only. Existing NPC components can also have
  // an enabled Engine tick; disable that second domain explicitly as well.
  if(c.kind==plane_component_ticks::Kind::live&&now.base_tick){c.base_changed=true;reinterpret_cast<Set>(image_base+0x41df200)(c.identity.pointer,false);if(!role_component_read(c,now))return false;}
  if(now.base_tick||(c.kind==plane_component_ticks::Kind::live&&now.custom_enabled)||
   (c.kind==plane_component_ticks::Kind::mesh&&now.aux_registration&&(now.aux_flags&1)))return false;
 }
 return true;
}
bool role_detach_restore(){
 if(!role_detach.mutated)return true;
 if(!role_detach_guard())return false;
 // Restore the graph before any component can run again.
 for(auto&a:role_detach.unit_arrays){uintptr_t data=0;int32_t cap=0;if(!read(a.address,data)||data!=a.data||!read(a.address+12,cap)||cap!=a.capacity)return false;std::memcpy(reinterpret_cast<void*>(data),a.values.data(),a.count*8);std::memcpy(reinterpret_cast<void*>(a.address+8),&a.count,4);}
 for(auto&a:role_detach.manager_arrays){uintptr_t data=0;int32_t cap=0;if(!read(a.address,data)||data!=a.data||!read(a.address+12,cap)||cap!=a.capacity)return false;std::memcpy(reinterpret_cast<void*>(data),a.values.data(),a.count*8);std::memcpy(reinterpret_cast<void*>(a.address+8),&a.count,4);}
 *reinterpret_cast<uintptr_t*>(role_npc.pointer+0xfa0)=role_unit.pointer;
 using Set=void(__fastcall*)(uintptr_t,bool);
 for(auto&c:role_detach.components)if(c.changed){const bool enabled=c.kind==plane_component_ticks::Kind::live?c.state.custom_enabled!=0:c.state.base_tick!=0;reinterpret_cast<Set>(c.setter)(c.identity.pointer,enabled);if(c.base_changed)reinterpret_cast<Set>(image_base+0x41df200)(c.identity.pointer,c.state.base_tick!=0);}
 reinterpret_cast<Set>(role_detach.unit_set)(role_unit.pointer,role_detach.unit_tick);
 reinterpret_cast<Set>(role_detach.npc_set)(role_npc.pointer,role_detach.npc_tick);
 *reinterpret_cast<uint8_t*>(role_npc.pointer+0x3f4)=role_detach.active;
 bool ok=role_detach_guard();uintptr_t link=0;ok=ok&&read(role_npc.pointer+0xfa0,link)&&link==role_unit.pointer;
 for(const auto&a:role_detach.unit_arrays)ok=role_array_same(a)&&ok;
 for(const auto&a:role_detach.manager_arrays)ok=role_array_same(a)&&ok;
 for(const auto&c:role_detach.components){plane_component_ticks::State now;ok=role_component_read(c,now)&&now.base_tick==c.state.base_tick&&now.custom_enabled==c.state.custom_enabled&&bool(now.aux_registration&&(now.aux_flags&1))==bool(c.state.aux_registration&&(c.state.aux_flags&1))&&ok;}
 if(ok){role_detach.mutated=false;role_health.forwarded_only=false;}return ok;
}
bool role_detach_apply(){
 if(!role_health.consumed||role_health.installed||!role_prepared||!role_detach_capture())return false;
 for(const auto&a:role_detach.unit_arrays)if(!role_array_same(a))return diagnostic_fail("role_arrays_changed_before_detach");
 for(const auto&a:role_detach.manager_arrays)if(!role_array_same(a))return diagnostic_fail("role_manager_changed_before_detach");
 auto slot=reinterpret_cast<void* volatile*>(role_unit.pointer+0x298);
 if(InterlockedCompareExchangePointer(slot,const_cast<uintptr_t*>(role_health_table.data()),reinterpret_cast<void*>(role_health.original))!=reinterpret_cast<void*>(role_health.original))return diagnostic_fail("role_health_install_raced");
 role_health.installed=true;role_detach.mutated=true;
 using Set=void(__fastcall*)(uintptr_t,bool);
 reinterpret_cast<Set>(role_detach.unit_set)(role_unit.pointer,false);reinterpret_cast<Set>(role_detach.npc_set)(role_npc.pointer,false);
 *reinterpret_cast<uint8_t*>(role_npc.pointer+0x3f4)=0;
 bool detached=role_components_disable();
 if(detached){
  role_health.forwarded_only=true;
  for(const auto&a:role_detach.unit_arrays)*reinterpret_cast<int32_t*>(a.address+8)=0;
  for(const auto&a:role_detach.manager_arrays){auto values=a.values;for(int i=int(a.remove);i<a.count-1;++i)values[i]=values[i+1];const int32_t count=a.count-1;std::memcpy(reinterpret_cast<void*>(a.data),values.data(),count*8);*reinterpret_cast<int32_t*>(a.address+8)=count;}
  *reinterpret_cast<uintptr_t*>(role_npc.pointer+0xfa0)=0;
  using Get=bool(__fastcall*)(uintptr_t);detached=!reinterpret_cast<Get>(role_detach.unit_get)(role_unit.pointer)&&!reinterpret_cast<Get>(role_detach.npc_get)(role_npc.pointer);
  for(const auto&a:role_detach.unit_arrays){int32_t n=-1;detached=read(a.address+8,n)&&n==0&&detached;}
  for(const auto&a:role_detach.manager_arrays){RoleWeakArray current;detached=role_array_capture(a.address,current)&&current.count==2&&detached;for(int i=0;i<current.count;++i)detached=current.values[i]!=a.values[a.remove]&&detached;}
 }
 return detached;
}
bool role_detach_trial(){
 static bool consumed=false;if(consumed)return diagnostic_fail("role_detach_trial_consumed");consumed=true;
 const bool detached=role_detach_apply();
 if(!role_detach.mutated)return false;
 const auto target=health_sample(ledger.raw_owned+0x320,role_health.target_functions);
 const auto routed=health_sample(role_unit.pointer+0x298,role_health_table);
 const bool forwarded=target.position==routed.position&&target.faction==routed.faction&&target.rate==routed.rate&&target.name==routed.name;
 int32_t plane_count=-1,unit_count=-1;read(role_detach.manager_arrays[0].address+8,plane_count);read(role_detach.manager_arrays[1].address+8,unit_count);
 bool empty=true;for(const auto&a:role_detach.unit_arrays){int32_t n=-1;empty=read(a.address+8,n)&&n==0&&empty;}
 const bool restored=role_detach_restore();const bool health_restored=restored&&role_health_restore();
 const auto path=directory+L"\\guest-role-detach-"+AC8_GUEST_REV_W+L".tsv";FILE*f=nullptr;
 if(!_wfopen_s(&f,path.c_str(),L"wb")&&f){std::fprintf(f,"npc_detached_from_ai\t%d\nunit_ai_arrays_empty\t%d\nmanager_planes_during_trial\t%d\nmanager_units_during_trial\t%d\nnpc_component_count\t%u\nunit_interface_forwarded\t%d\noriginal_graph_restored\t%d\noriginal_health_interface_restored\t%d\nnpc_destroy_called\t0\nplayer_activated\t0\n",detached?1:0,empty?1:0,plane_count,unit_count,unsigned(role_detach.components.size()),forwarded?1:0,restored?1:0,health_restored?1:0);std::fclose(f);}
 native_failure=detached&&forwarded&&restored&&health_restored?"npc_detachment_and_unit_forwarding_restored":"npc_detach_or_restore_unverified";
 return detached&&forwarded&&restored&&health_restored;
}
