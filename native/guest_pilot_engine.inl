// Exact-build host adapter. This attaches to the already committed player role;
// it never spawns a plane, captures the host's trajectory, or releases AI ticks.
namespace pilot_engine {
uintptr_t image=0;DWORD thread=0;std::wstring directory;const char*reason="not_bound";
struct Id{uintptr_t p=0;int32_t index=-1,serial=0;};
Id world,pc,unit,manager,network,parts,root;std::array<Id,4>actors{};
std::array<uint32_t,4>aircraft{};Id retired_npc;
bool bound=false;uint64_t native_steps=0;std::array<float,6>last_controls{};
bool bytes(uintptr_t p,void*out,size_t n){
 if(p<0x10000||p>=0x800000000000ULL||!n||n>4096||p+n>=0x800000000000ULL)return false;
 __try{memcpy(out,reinterpret_cast<void*>(p),n);return true;}__except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
template<class T>bool read(uintptr_t p,T&v){return bytes(p,&v,sizeof v);}
bool slot(int32_t index,uintptr_t&at){uintptr_t chunks=0,chunk=0;int32_t n=0,count=0;
 return index>=0&&read(image+0xdc60cd0+0x24,n)&&index<n&&n<=0x1000000&&read(image+0xdc60cd0+0x2c,count)&&index/65536<count&&
  read(image+0xdc60cd0+0x10,chunks)&&read(chunks+uintptr_t(index/65536)*8,chunk)&&(at=chunk+uintptr_t(index&65535)*24)!=0;
}
bool identity(uintptr_t p,Id&out,bool mint=false){int32_t index=-1,serial=0;uint32_t flags=0;uintptr_t at=0,actual=0;
 if(!read(p+12,index)||!slot(index,at)||!read(at,actual)||actual!=p||!read(at+16,serial)||!read(p+8,flags)||(flags&0x60000010))return false;
 if(!serial&&mint){using Mint=int32_t(__fastcall*)(uintptr_t,int32_t);const auto assigned=reinterpret_cast<Mint>(image+0x1aae560)(image+0xdc60cd0,index);if(!read(at+16,serial)||serial!=assigned)return false;}if(serial<=0)return false;
 out={p,index,serial};return true;
}
bool same(const Id&i){Id now;return identity(i.p,now)&&i.index==now.index&&i.serial==now.serial;}
bool retired(const Id&i){uintptr_t at=0,p=0;int32_t serial=0;return slot(i.index,at)&&read(at,p)&&read(at+16,serial)&&(p!=i.p||serial!=i.serial);}
bool in_world(const Id&i){uintptr_t level=0,w=0;return same(i)&&read(i.p+0x20,level)&&read(level+0xc0,w)&&w==world.p;}
bool number(const std::string&s,uint64_t&v){if(s.empty()||s.size()>20||s[0]=='-'||s[0]=='+')return false;errno=0;char*e=nullptr;v=strtoull(s.c_str(),&e,0);return !errno&&e==s.c_str()+s.size();}
bool file(const wchar_t*name,std::map<std::string,std::string>&out){
 FILE*f=nullptr;if(_wfopen_s(&f,(directory+L"\\"+name).c_str(),L"rb")||!f)return false;char b[4097]{};size_t n=fread(b,1,sizeof b,f);fclose(f);if(n>4096)return false;
 std::string s(b,n);size_t at=0;while(at<s.size()){auto end=s.find('\n',at);if(end==std::string::npos)return false;auto line=s.substr(at,end-at);at=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos||!out.emplace(line.substr(0,tab),line.substr(tab+1)).second)return false;}return true;
}
bool components_fenced(){
 const uintptr_t set=actors[1].p+0x218;std::array<uint8_t,0x38>before{},after{};uintptr_t data=0,external=0;int32_t n=0,cap=0,bits=0,maxbits=0,free=0;
 if(!bytes(set,before.data(),before.size()))return false;
 memcpy(&data,before.data(),8);memcpy(&n,before.data()+8,4);memcpy(&cap,before.data()+12,4);memcpy(&external,before.data()+0x20,8);memcpy(&bits,before.data()+0x28,4);memcpy(&maxbits,before.data()+0x2c,4);memcpy(&free,before.data()+0x34,4);
 if(n<1||n>512||bits!=n||cap<n||cap>4096||free<0||free>n||maxbits<bits||maxbits>4096||(!external&&bits>128))return false;
 const auto bitmap=external?external:set+0x10;unsigned allocated=0;
 for(int i=0;i<bits;++i){uint32_t mask=0;if(!read(bitmap+uintptr_t(i/32)*4,mask))return false;if(!(mask&(1u<<(i%32))))continue;++allocated;
  uintptr_t p=0,owner=0,vt=0,setter=0,getter=0;Id id;uint8_t base_tick=1,custom=1;
  if(!read(data+uintptr_t(i)*16,p)||!read(p+0x90,owner)||owner!=actors[1].p||!identity(p,id,true)||!read(p,vt)||!read(vt+0x3d8,setter)||!read(vt+0x3e8,getter)||setter<image||getter<image||!read(p+0x3b,base_tick)||base_tick)return false;
  auto kind=plane_component_ticks::classify({setter-image,getter-image});if(kind==plane_component_ticks::Kind::unknown)return false;
  if(kind==plane_component_ticks::Kind::live&&(!read(p+0xd3,custom)||custom))return false;
  if(kind==plane_component_ticks::Kind::mesh){uintptr_t registration=0;uint8_t flags=0;if(!read(p+0xbd0,registration)||(registration&&(!read(registration,flags)||(flags&1))))return false;}
 }
 return allocated==unsigned(n-free)&&bytes(set,after.data(),after.size())&&before==after;
}
bool graph(){
 if(!bound||GetCurrentThreadId()!=thread||!same(world)||!same(pc)||!in_world(unit)||!same(manager)||!retired(retired_npc))return false;
 uintptr_t pointer=0,vt=0;uint8_t active=0,player_auto=1,ai_auto=1,tick=1;
 for(unsigned i=0;i<4;++i)if(!in_world(actors[i])||!read(actors[i].p+0x3f4,active)||active!=1)return false;
 if(!read(pc.p+0x2d0,pointer)||pointer!=actors[0].p||!read(actors[0].p+0x2c8,pointer)||pointer!=pc.p||!read(actors[1].p+0x2c8,pointer)||pointer||
  !read(actors[1].p,vt)||vt!=image+0xcc01cc8||!read(actors[1].p+0x2a0,player_auto)||player_auto||!read(actors[1].p+0x2a1,ai_auto)||ai_auto||!read(actors[1].p+0x33,tick)||tick)return false;
 if(!same(network)||!same(parts)||!same(root)||!read(actors[1].p+0xed0,pointer)||pointer!=network.p||!read(actors[1].p+0x1328,pointer)||pointer!=parts.p||!read(actors[1].p+0x1a0,pointer)||pointer!=root.p)return false;
 for(unsigned off:{0x2c0u,0x2d0u,0x2e0u,0x2f0u,0x300u,0x310u}){int32_t n=-1;if(!read(unit.p+off+8,n)||n)return false;}
 uintptr_t list=0;int32_t count=-1;if(!read(manager.p+0x70,list)||!read(manager.p+0x78,count)||count!=2)return false;
 uint64_t weak[2]{};if(!bytes(list,weak,sizeof weak)||weak[0]==weak[1])return false;
 for(unsigned i=0;i<2;++i){const auto wanted=uint64_t(uint32_t(actors[i+2].index))|(uint64_t(uint32_t(actors[i+2].serial))<<32);if(weak[0]!=wanted&&weak[1]!=wanted)return false;}
 for(unsigned i=0;i<2;++i){const auto m=actors[1].p+(i?0x3c60:0x2268);uint8_t mode=9;if(!read(m+0x860,pointer)||pointer!=actors[1].p+0xf48||!read(m+0x8b4,mode)||mode!=i||!read(m+0xe20,vt)||vt!=image+0xbefcb80)return false;}
 uintptr_t table=0,callback=0;if(!read(unit.p+0x298,table)||table==image+0xcb22e20||!read(table,callback))return false;
 MEMORY_BASIC_INFORMATION memory{};auto module=GetModuleHandleW(L"ac8_guest_player_init_r19.dll");if(!module||!VirtualQuery(reinterpret_cast<void*>(callback),&memory,sizeof memory)||memory.AllocationBase!=module)return false;
 return components_fenced();
}
bool fingerprint(uintptr_t rva,const char*hex){
 unsigned char expected[16]{},actual[16]{};for(unsigned i=0;i<16;++i){unsigned v=0;if(sscanf_s(hex+2*i,"%2x",&v)!=1)return false;expected[i]=uint8_t(v);}return bytes(image+rva,actual,16)&&memcmp(expected,actual,16)==0;
}
bool bind(const std::map<std::string,std::string>&request){
 reason="replacement_receipt_unverified";
 std::map<std::string,std::string>commit;if(!file(L"guest-role-commit-r19.tsv",commit)||commit["npc_retired_verified"]!="1"||commit["unit_preserved"]!="1"||commit["player_visible_active"]!="1")return false;
 uint64_t value=0;reason="replacement_identity_unverified";
 for(auto pair:std::array<std::pair<const char*,Id*>,3>{{{"world",&world},{"unit",&unit},{"player",&actors[1]}}}){
  if(!number(commit[pair.first],value)||!identity(value,*pair.second))return false;
  if(std::string(pair.first)!="world"){uint64_t index=0,serial=0;if(!number(commit[std::string(pair.first)+"_index"],index)||!number(commit[std::string(pair.first)+"_serial"],serial)||index!=uint32_t(pair.second->index)||serial!=uint32_t(pair.second->serial))return false;}
 }
 reason="host_or_other_wingmen_identity_unverified";auto requested=[&](const char*key,Id&id){auto it=request.find(key);return it!=request.end()&&number(it->second,value)&&identity(value,id);};
 if(!requested("controller",pc)||!requested("host",actors[0])||!requested("other0",actors[2])||!requested("other1",actors[3])||!requested("manager",manager))return false;
 if(!number(commit["old_npc"],value))return false;retired_npc.p=value;if(!number(commit["old_npc_index"],value)||value>INT32_MAX)return false;retired_npc.index=int32_t(value);
 if(!number(commit["old_npc_serial"],value)||value>INT32_MAX)return false;retired_npc.serial=int32_t(value);
 reason="owned_network_parts_or_root_unverified";uintptr_t p=0;if(!read(actors[1].p+0xed0,p)||!identity(p,network)||!read(actors[1].p+0x1328,p)||!identity(p,parts)||!read(actors[1].p+0x1a0,p)||!identity(p,root,true))return false;
 for(unsigned i=0;i<4;++i){auto it=request.find("aircraft"+std::to_string(i));if(it==request.end()||!number(it->second,value)||!value||value>65535)return false;aircraft[i]=uint32_t(value);}
 reason="flight_native_entry_fingerprint_unverified";if(aircraft[1]!=23||!fingerprint(0x4d326e0,"488bc448895808488970104889781855")||!fingerprint(0x4d32580,"4883ec38f64218010f57c9f30f1005fd")||
  !fingerprint(0x4d344f0,"48895c2408574883ec20488db9c00900")||!fingerprint(0x74d8c00,"488bc448895808488970104889781855")||
  !fingerprint(0x4d318a0,"40534881ec80000000f30f100d777957")||!fingerprint(0x3fdebc0,"4881ec78010000488b89a00100004885"))return false;
 reason="replacement_flight_graph_unverified";bound=true;if(!graph()){bound=false;return false;}reason="committed_f14_model_bound";return true;
}
bool pose(unsigned index,ac8pilot::Pose&out){
 if(index>3||!same(actors[index]))return false;uintptr_t component=0,owner=0;Id id;std::array<double,4>q{};int32_t hp=0;
 if(!read(actors[index].p+0x1a0,component)||!identity(component,id)||!read(component+0x90,owner)||owner!=actors[index].p||!bytes(component+0x200,q.data(),32)||!bytes(component+0x220,out.position.data(),24)||!read(actors[index].p+0xda8,hp)||!read(actors[index].p+0x3b4,out.max_health))return false;
 out.role=index;out.aircraft=aircraft[index];for(unsigned i=0;i<4;++i)out.rotation[i]=float(q[i]);out.health=std::clamp(float(hp)*0.1f,0.f,out.max_health);
 out.speed=0;if(index==1&&!read(actors[1].p+0x2268+0xb0,out.speed))return false;return ac8pilot::finite(out)&&same(id);
}
bool sync_pose(){
 if(!graph())return false;const auto model=actors[1].p+0x2268;std::array<float,4>q{};std::array<double,3>p{},angles{};float scale=0;
 if(!bytes(model+0x8d0,q.data(),16)||!bytes(model+0x8e0,p.data(),24)||!read(image+0xdc4c03c,scale)||scale!=100)return false;
 ac8player::Pose check{p,q};if(!ac8player::finite(check))return false;
 using Angles=double*(__fastcall*)(const float*,double*);reinterpret_cast<Angles>(image+0x4d318a0)(q.data(),angles.data());
 constexpr double degrees=57.29577951308232;double position[]={p[2]*scale,-p[0]*scale,p[1]*scale},rotation[]={-angles[0]*degrees,-angles[1]*degrees,angles[2]*degrees};
 for(unsigned i=0;i<3;++i)if(!std::isfinite(position[i])||fabs(position[i])>1e9||!std::isfinite(rotation[i]))return false;
 using Move=bool(__fastcall*)(uintptr_t,const double*,const double*,bool,void*,uint8_t);
 return reinterpret_cast<Move>(image+0x3fdebc0)(actors[1].p,position,rotation,false,nullptr,0)&&graph();
}
bool apply(const ac8input::Frame&frame,unsigned steps){
 if(!steps||steps>6||!graph()||!ac8player::controls(frame,last_controls))return false;
 struct Controls{std::array<float,6>axes;uint8_t flags=0;uint8_t pad[7]{};}controls{last_controls};
 const auto model=actors[1].p+0x2268;
 for(unsigned i=0;i<steps;++i){if(!graph())return false;using Input=void(__fastcall*)(uintptr_t,const void*);reinterpret_cast<Input>(image+0x4d32580)(model,&controls);
  using Step=void(__fastcall*)(uintptr_t,float);reinterpret_cast<Step>(image+0x4d326e0)(model,1.f/60.f);++native_steps;
  ac8player::Pose p;if(!bytes(model+0x8d0,p.rotation.data(),16)||!bytes(model+0x8e0,p.position.data(),24)||!ac8player::finite(p))return false;
 }
 return sync_pose();
}
struct Checkpoint{
 plane_initial_state::Snapshot state{};std::array<uint8_t,0x1648>host_before{};bool captured=false;
}checkpoint;
struct CheckpointAccess{
 bool read(uintptr_t p,void*out,size_t n){return bytes(p,out,n);}
 bool qpc(uint64_t&out){LARGE_INTEGER q{};if(!QueryPerformanceCounter(&q))return false;out=uint64_t(q.QuadPart);return true;}
};
bool checkpoint_capture(){
 if(!graph()||checkpoint.captured)return false;CheckpointAccess access;const char*error=nullptr;
 if(!plane_initial_state::capture(access,actors[1].p,image,1,checkpoint.state,error)){reason=error;return false;}
 if(!bytes(actors[0].p+0x2268,checkpoint.host_before.data(),4096)||!bytes(actors[0].p+0x3268,checkpoint.host_before.data()+4096,checkpoint.host_before.size()-4096))return false;
 checkpoint.captured=true;return true;
}
bool checkpoint_restore(){
 // A self checkpoint restores only named scalar cache fields. It never stages
 // a host snapshot, model parameter block, vtable, pointer or component header.
 if(!checkpoint.captured||!graph())return false;const auto&s=checkpoint.state;uintptr_t cache[5]{};
 const unsigned offsets[]={0x98,0x140,0x150,0x160,0x170};const uintptr_t vtables[]={0xbfecc70,0xbfecd10,0xbfecd50,0xbfeccd0,0xbfecd30};
 for(unsigned i=0;i<5;++i){uintptr_t ref=0,vt=0;int32_t strong=0;if(!read(network.p+offsets[i],cache[i])||!read(network.p+offsets[i]+8,ref)||cache[i]!=ref+16||!read(cache[i],vt)||vt!=image+vtables[i]||!read(ref+8,strong)||strong<=0)return false;}
 const uint8_t*blocks[]={s.main.data(),s.aux140.data(),s.aux150.data(),s.aux160.data(),s.aux170.data()};
 for(const auto&f:plane_initial_state::fields()){if(!graph())return false;auto target=(f.cache==5?actors[1].p:cache[f.cache])+f.offset;auto source=f.cache==5?reinterpret_cast<const void*>(&s.timestamp):static_cast<const void*>(blocks[f.cache]+f.offset);memcpy(reinterpret_cast<void*>(target),source,f.size);uint8_t actual[8]{};if(!bytes(target,actual,f.size)||memcmp(actual,source,f.size))return false;}
 using Reset=void(__fastcall*)(uintptr_t);reinterpret_cast<Reset>(image+0x4d344f0)(actors[1].p+0x3c60);
 for(unsigned i=0;i<2;++i){auto model=actors[1].p+(i?0x3c60:0x2268);using Consume=void(__fastcall*)(uintptr_t,uintptr_t);reinterpret_cast<Consume>(image+0x74d8c00)(network.p,model);using Input=void(__fastcall*)(uintptr_t,uintptr_t);reinterpret_cast<Input>(image+0x4d32580)(model,cache[4]+8);}
 const bool restored=sync_pose();std::array<uint8_t,0x1648>host_after{};
 const bool host_preserved=bytes(actors[0].p+0x2268,host_after.data(),4096)&&bytes(actors[0].p+0x3268,host_after.data()+4096,host_after.size()-4096)&&host_after==checkpoint.host_before;
 FILE*f=nullptr;if(!_wfopen_s(&f,(directory+L"\\guest-pilot-checkpoint.tsv").c_str(),L"wb")&&f){fprintf(f,"own_checkpoint_restored\t%d\nhost_model_unchanged_during_paused_trial\t%d\nnative_steps\t%llu\n",restored?1:0,host_preserved?1:0,static_cast<unsigned long long>(native_steps));fclose(f);}
 return restored&&host_preserved;
}
}
