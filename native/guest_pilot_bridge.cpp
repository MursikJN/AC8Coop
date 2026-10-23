#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "guest_pilot_loopback.h"
#include "guest_player_physics.h"
#include "plane_component_ticks.h"
#include "plane_flight_state.h"
#ifndef AC8_R27_EMBEDDED_PILOT
#define AC8_GUEST_PILOT_TRANSPORT
#include "connection_test.cpp"
#endif
#include <map>
#include <string>
#include <vector>
#include <cerrno>
#include <ctime>
#include <dbghelp.h>
#include <xinput.h>
#include "guest_pilot_input.h"
#ifndef AC8_PILOT_REV
#define AC8_PILOT_REV r20
#endif
#define PILOT_STR_(x) #x
#define PILOT_STR(x) PILOT_STR_(x)
#define PILOT_WIDE_(x) L##x
#define PILOT_WIDE(x) PILOT_WIDE_(x)
#define PILOT_REV_W PILOT_WIDE(PILOT_STR(AC8_PILOT_REV))
#include "guest_pilot_engine.inl"
#ifdef AC8_OWNER_SIM_R30
#include "owner_flight.h"
#endif
#ifdef AC8_OWNER_NATIVE_R31
#include "guest_owner_native.inl"
#endif
namespace pilot_bridge {
bool active=false,is_host=true,local=true,local_paused_proof=false,checkpoint_done=false;
uint64_t generation=0,local_token=0,sequence=0,last_report=0,last_send=0,trial_deadline=0;
uint32_t revision=0;const char*detail="idle";
#ifdef AC8_R27_EMBEDDED_PILOT
ac8pilot::Context room_binding{};
#endif
ac8pilot::Loopback loop;ac8pilot::Gate gate;ac8pilot::Cadence cadence;ac8pilot::Frame latest{};
uint64_t received_state_ms=0,accepted_inputs=0;bool have_state=false,loaded_sent=false;
#ifdef AC8_OWNER_NATIVE_R31
owner_native::Backend owner_backend;
ac8owner::LocalPilot<owner_native::Backend> owner_pilot(owner_backend);
ac8owner::Receiver owner_receiver;
ac8input::Frame local_input{};uint64_t local_input_at=0;
uint64_t owner_started_at=0;
std::map<std::string,std::string> owner_local_request;
bool owner_controls_allowed(){return local||ac8coop_transport::controls_allowed();}
#endif
using pilot_engine::read;using pilot_engine::bytes;
uint64_t microseconds(){LARGE_INTEGER q{},f{};if(!QueryPerformanceCounter(&q)||!QueryPerformanceFrequency(&f)||f.QuadPart<=0)return 0;return uint64_t(q.QuadPart/f.QuadPart)*1000000+uint64_t(q.QuadPart%f.QuadPart)*1000000/uint64_t(f.QuadPart);}
bool env(const wchar_t*key,wchar_t*out,DWORD n){auto size=GetEnvironmentVariableW(key,out,n);return size>0&&size<n;}
bool setup(){
 wchar_t marker[32]{},out[32768]{},scripts[32768]{},actual[32768]{},expected[32768]{};
 const bool development=env(L"AC8_LOCAL_ADAPTER_DEV",marker,32)&&!wcscmp(marker,L"25201480");
 const bool enabled=env(L"AC8_GUEST_PILOT",marker,32)&&!wcscmp(marker,L"25201480");
 if((!development&&!enabled)||!env(L"AC8_COOP_RECON_OUTPUT",out,32768)||!env(L"AC8_LOCAL_SCRIPTS",scripts,32768))return false;
 HMODULE self=nullptr;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&setup),&self)||!GetModuleFileNameW(self,actual,32768))return false;
#ifdef AC8_R27_EMBEDDED_PILOT
 const auto path=std::wstring(scripts)+L"\\..\\..\\..\\ac8_steam_coop_"+PILOT_REV_W+L".dll";
#else
 const auto path=std::wstring(scripts)+L"\\..\\..\\..\\ac8_guest_pilot_"+PILOT_REV_W+L".dll";
#endif
 if(!GetFullPathNameW(path.c_str(),32768,expected,nullptr)||_wcsicmp(actual,expected)||!GetModuleFileNameW(nullptr,actual,32768))return false;
 auto name=wcsrchr(actual,L'\\');if(!name||_wcsicmp(name+1,L"AceCombat8.exe"))return false;
 if(!pilot_engine::thread)pilot_engine::thread=GetCurrentThreadId();if(pilot_engine::thread!=GetCurrentThreadId())return false;
 pilot_engine::image=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));pilot_engine::directory=out;return true;
}
void binary(const wchar_t*name,const ac8pilot::Frame&frame){
 if(!ac8pilot::valid(frame))return;const auto b=ac8pilot::encode(frame);FILE*f=nullptr;
 if(!_wfopen_s(&f,(pilot_engine::directory+L"\\"+name).c_str(),L"wb")&&f){fwrite(b.data(),1,b.size(),f);fclose(f);}
}
ac8pilot::Context context(){return local?loop.context():
#ifdef AC8_R27_EMBEDDED_PILOT
 ac8coop_transport::context();
#else
 ac8pilot_transport::context();
#endif
}
bool send(ac8pilot::Frame f){return local?loop.send_frame(f):
#ifdef AC8_R27_EMBEDDED_PILOT
 ac8coop_transport::send(f);
#else
 ac8pilot_transport::send(f);
#endif
}
bool paused(){
 std::map<std::string,std::string>r;uint64_t created=0;
 if(!pilot_engine::file(L"guest-pilot-clock.tsv",r)||!pilot_engine::number(r["created_unix"],created)||std::llabs(int64_t(time(nullptr))-int64_t(created))>1)return true;
 return r["paused"]!="0";
}
void report(){
 const auto ctx=context();FILE*f=nullptr;if(_wfopen_s(&f,(pilot_engine::directory+L"\\guest-pilot-status.tsv").c_str(),L"wb")||!f)return;
 fprintf(f,"revision\t%s\nstate\t%s\nactive\t%d\nrole\t%s\ntransport\t%s\nport\t%u\nlocal_test_token\t%llu\ngeneration\t%llu\nconfiguration_revision\t%u\npeer_loaded\t%d\nreal_guest_connected\t%d\nspectating\t%d\naccepted_inputs\t%llu\nnative_steps\t%llu\nstate_sequence\t%llu\nlast_roll_input\t%.9g\nall_story_commands_bridged\t0\nfull_mission_replication\t0\n",PILOT_STR(AC8_PILOT_REV),detail,active?1:0,is_host?"host":"guest",local?"loopback_test":"steam",unsigned(loop.port),static_cast<unsigned long long>(local?local_token:0),static_cast<unsigned long long>(generation),revision,gate.loaded?1:0,!local&&ctx.peer&&gate.loaded?1:0,gate.spectating?1:0,static_cast<unsigned long long>(accepted_inputs),static_cast<unsigned long long>(pilot_engine::native_steps),static_cast<unsigned long long>(sequence),double(pilot_engine::last_controls[2]));
 fprintf(f,"engine_detail\t%s\n",pilot_engine::reason);
#ifdef AC8_OWNER_NATIVE_R31
 fprintf(f,"owner_native_candidate\t1\nowner_ready\t%d\nowner_pointer\t0x%llx\nowner_index\t%d\nowner_serial\t%d\nowner_detail\t%s\nowner_native_steps\t%llu\nowner_cleanup\t%s\nowner_cleanup_reason\t%s\n",owner_backend.seeded&&!owner_backend.closing?1:0,static_cast<unsigned long long>(owner_backend.actor.p),owner_backend.actor.index,owner_backend.actor.serial,owner_backend.detail,static_cast<unsigned long long>(owner_backend.steps),owner_backend.ledger.status,owner_backend.ledger.reason);
 fprintf(f,"owner_camera_tracked\t%d\n",owner_backend.camera_actor.p?1:0);
 fprintf(f,"owner_template_retained\t%d\nowner_template_roots_owned\t%d\nowner_dependency_field\t%s\nowner_dependency_failure\t%s\n",owner_backend.class_root.captured&&owner_backend.cdo_root.captured?1:0,int(owner_backend.class_root.owned)+int(owner_backend.cdo_root.owned),owner_backend.dependency_field,owner_backend.dependency_failure);
 fprintf(f,"owner_cleanup_complete\t%d\n",owner_backend.cleanup_complete?1:0);
 fprintf(f,"owner_ticks_detached\t%d\nowner_destroy_accepted\t%d\nowner_gc_safe\t%d\nowner_tick_component_count\t%u\n",owner_backend.ticks_detached?1:0,owner_backend.ledger.destroy_accepted?1:0,owner_backend.gc_safe()?1:0,unsigned(owner_backend.tick_components.size()));
 const auto sound_error=owner_backend.sound_objects_reason();
 fprintf(f,"owner_preflight_ready\t%d\nowner_sound_ready\t%d\nowner_sound_reason\t%s\nowner_input_samples\t%llu\nowner_local_sequence\t%llu\nowner_camera_retired\t%d\n",owner_backend.configured?1:0,sound_error?0:1,sound_error?sound_error:"ready",static_cast<unsigned long long>(accepted_inputs),static_cast<unsigned long long>(owner_backend.local_sequence),owner_backend.camera_actor.p&&pilot_engine::retired(owner_backend.camera_actor)?1:0);
 const auto objects_error=owner_backend.world_objects_reason();
 fprintf(f,"owner_world_objects_checked\t%d\nowner_world_objects_ready\t%d\nowner_world_objects_reason\t%s\nowner_combat_zone_pointer\t0x%llx\nowner_actor_mapper_pointer\t0x%llx\n",owner_backend.world_objects_bound?1:0,objects_error?0:1,objects_error?objects_error:"ready",static_cast<unsigned long long>(owner_backend.world_objects.zone.p),static_cast<unsigned long long>(owner_backend.world_objects.mapper.p));
 uint64_t owner_key=0;if(owner_backend.network.p)pilot_engine::read(owner_backend.network.p+0x28,owner_key);
 fprintf(f,"owner_network_key\t%016llx\nowner_expected_key\t%016llx\nowner_endplay_graph_verified\t%d\n",static_cast<unsigned long long>(owner_key),static_cast<unsigned long long>(owner_backend.key),owner_backend.endplay_graph_verified?1:0);
#endif
 fclose(f);last_report=GetTickCount64();
}
ac8input::Assignment assignment(){const auto c=context();return {c.peer,c.remote,c.nonce,generation,revision,1,23,is_host,pilot_engine::bound,gate.loaded,pilot_engine::bound,pilot_engine::bound,pilot_engine::bound};}
void consume(const ac8pilot::Frame&f,uint64_t now){
 const auto ctx=context();if(!ctx.peer)return;
 if(is_host){
  if(gate.context.peer!=ctx.peer||gate.context.nonce!=ctx.nonce||gate.context.remote!=ctx.remote)gate.bind(ctx,generation,revision);
#ifdef AC8_OWNER_NATIVE_R31
  owner_receiver.release(gate.loaded&&!gate.spectating);
  if(f.kind==ac8pilot::Kind::owner_state){owner_receiver.accept(f,now);return;}
#endif
  if(gate.accept(f,now,assignment())&&f.kind==ac8pilot::Kind::input)++accepted_inputs;
 }else if(f.kind==ac8pilot::Kind::state&&ac8pilot::matches(f,ctx)&&(!have_state||f.sequence>latest.sequence)){
  if(have_state&&(f.generation!=latest.generation||f.revision!=latest.revision)){loaded_sent=false;}
  latest=f;have_state=true;received_state_ms=now;generation=f.generation;revision=f.revision;binary(L"guest-pilot-state.ac8p",f);
 }else if(f.kind==ac8pilot::Kind::stop){have_state=false;loaded_sent=false;detail="host_stopped";}
}
bool start(){
 if(active)return false;std::map<std::string,std::string>r;uint64_t created=0;
 if(!pilot_engine::file(L"guest-pilot-request.tsv",r)||!pilot_engine::number(r["created_unix"],created)||std::llabs(int64_t(time(nullptr))-int64_t(created))>3)return false;
 if(r["role"]!="host"&&r["role"]!="guest")return false;is_host=r["role"]=="host";
#if defined(AC8_OWNER_SIM_R30) && !defined(AC8_OWNER_NATIVE_R31)
 // R29's host-driven replacement is not a valid owner-simulation backend.
 // Do not enter it, fabricate a preparation receipt, or silently fall back to
 // remote stick simulation. Native stock initialization in the isolated guest
 // world and selector teardown still require a verified game-thread backend.
 pilot_engine::reason="r30_blocked_guest_stock_bootstrap_and_native_sortie_backend_unverified";
 return false;
#else
 uint64_t value=0;
 if(r["transport"]!="loopback"&&r["transport"]!="steam")return false;local=r["transport"]=="loopback";
#ifdef AC8_OWNER_NATIVE_R31
 if(local){wchar_t marker[32]{};if(!env(L"AC8_OWNER_LOCAL_LAB",marker,32)||wcscmp(marker,L"25201480"))return false;owner_local_request=r;}
#endif
 if(!pilot_engine::number(r["generation"],generation)||!generation||!pilot_engine::number(r["revision"],value)||!value||value>UINT32_MAX)return false;revision=uint32_t(value);
 local_paused_proof=local&&is_host&&r["paused_proof"]=="1";
 if(is_host){if(!pilot_engine::bind(r))return false;if(local_paused_proof&&!pilot_engine::checkpoint_capture())return false;}
 if(local){uint64_t port=0;if(!pilot_engine::number(r["port"],port)||port>65535||!pilot_engine::number(r["token"],local_token)||!local_token||!loop.open(is_host,uint16_t(port),local_token))return false;}
 else{
#ifdef AC8_R27_EMBEDDED_PILOT
  if(!ac8coop_transport::session_matches(generation,revision))return false;
  const auto ctx=ac8coop_transport::context();if(ctx.host!=is_host||!pilot_engine::number(r["peer"],value)||ctx.peer!=value)return false;
  room_binding=ctx;
#ifdef AC8_OWNER_NATIVE_R31
  if(is_host)owner_receiver.bind(ctx,generation,revision);
  else if(!owner_backend.configure_request(r,generation,revision,ctx)){pilot_engine::reason=owner_backend.reason();return false;}
#endif
#else
  if(!pilot_engine::number(r["peer"],value)||r["peer"].size()!=17)return false;
  wchar_t steam_path[32768]{};auto steam=GetModuleHandleW(L"steam_api64.dll");if(!steam||!GetModuleFileNameW(steam,steam_path,32768))return false;
  std::wstring peer(r["peer"].begin(),r["peer"].end()),out=pilot_engine::directory+L"\\pilot-connection";CreateDirectoryW(out.c_str(),nullptr);
  SetEnvironmentVariableW(L"AC8_CONNECTION_TEST",L"25201480");SetEnvironmentVariableW(L"AC8_CONNECTION_OUTPUT",out.c_str());SetEnvironmentVariableW(L"AC8_CONNECTION_ROLE",is_host?L"host":L"guest");SetEnvironmentVariableW(L"AC8_CONNECTION_PEER",peer.c_str());SetEnvironmentVariableW(L"AC8_CONNECTION_STEAM_DLL",steam_path);
  ac8pilot_transport::start();
#endif
 }
 cadence={};gate={};have_state=loaded_sent=checkpoint_done=false;sequence=accepted_inputs=0;last_send=0;active=true;detail=local?"waiting_local_test_peer":"waiting_steam_peer";
#ifdef AC8_OWNER_NATIVE_R31
 owner_started_at=GetTickCount64();
#endif
 trial_deadline=local_paused_proof?GetTickCount64()+6000:0;report();return true;
#endif
}
void stop(bool restore){
 if(active){ac8pilot::Frame f;f.kind=ac8pilot::Kind::stop;f.generation=generation;f.revision=revision;send(f);}
 if(local)loop.close();
#ifndef AC8_R27_EMBEDDED_PILOT
 else ac8pilot_transport::stop();
#endif
 gate.lease.revoke();gate.loaded=false;active=false;
#ifdef AC8_OWNER_NATIVE_R31
 owner_receiver.stop();local_input={};local_input_at=0;
 if(ac8owner::needs_owner_cleanup(is_host,owner_backend.camera_actor.p!=0)||owner_backend.class_root.captured||owner_backend.cdo_root.captured){owner_pilot.stop();owner_backend.release();}
#endif
 if(restore&&local_paused_proof&&!checkpoint_done){checkpoint_done=pilot_engine::checkpoint_restore();detail=checkpoint_done?"local_trial_stopped_and_own_checkpoint_restored":"local_trial_restore_unverified";}
 else detail="pilot_transport_stopped";report();
}
void tick(){
 if(!active){
#ifdef AC8_OWNER_NATIVE_R31
  if(owner_backend.closing){owner_backend.release();if(GetTickCount64()-last_report>=250)report();}
#endif
  return;
 }
 if(local){if(!loop.poll(consume)){
#ifdef AC8_OWNER_NATIVE_R31
  stop(false);detail=loop.error;report();return;
#else
  gate.lease.revoke();gate.loaded=false;detail=loop.error;
#endif
 }}
 else{
#ifdef AC8_R27_EMBEDDED_PILOT
  if(!ac8coop_transport::session_matches(generation,revision)){detail="room_or_sortie_changed";stop(false);return;}
  const auto bound=ac8coop_transport::context();if(bound.peer!=room_binding.peer||bound.nonce!=room_binding.nonce||bound.remote!=room_binding.remote){detail="authenticated_room_changed";stop(false);return;}
  ac8pilot::Frame f;uint64_t at=0;while(ac8coop_transport::take(f,at))consume(f,at);
#else
  ac8pilot_transport::poll();ac8pilot::Frame f;uint64_t at=0;while(ac8pilot_transport::take(f,at))consume(f,at);
#endif
 }
 const auto now=GetTickCount64();
 if(trial_deadline&&now>=trial_deadline){stop(true);return;}
 if(is_host){
  if(!pilot_engine::graph()){detail="host_role_graph_lost";stop(false);return;}
#ifdef AC8_OWNER_NATIVE_R31
  if(!gate.loaded&&now-owner_started_at>120000){stop(false);detail="owner_native_loading_timeout";report();return;}
  if(gate.loaded&&!gate.spectating&&!paused()&&now>=gate.loaded_ms&&now-gate.loaded_ms>1000&&(!owner_receiver.have||now-owner_receiver.received_ms>1000)){
   stop(false);detail="owner_motion_timeout";report();return;
  }
#endif
  const auto ctx=context();if(!ctx.peer){gate.lease.revoke();gate.loaded=false;cadence.advance(microseconds(),true);detail="waiting_authenticated_peer";}
  else{
#ifdef AC8_OWNER_NATIVE_R31
   // The host displays authenticated owner motion; it never integrates the
   // guest stick or invokes the guest model's native Step in this branch.
   ac8pilot::Pose remote;
   if(gate.spectating)owner_receiver.died();
   if(gate.loaded&&!paused()&&owner_controls_allowed()&&owner_receiver.sample(now,remote)){
    auto f=owner_receiver.latest;f.poses[0]=remote;binary(L"guest-owner-remote.ac8p",f);
   }
   detail=gate.loaded?"host_receives_guest_owned_motion":"waiting_guest_stock_model_loaded";
#else
   ac8input::Frame input;const bool fresh=gate.lease.sample(now,input);const bool held=!fresh||(!local_paused_proof&&paused())||gate.spectating
#ifdef AC8_R27_EMBEDDED_PILOT
    ||!ac8coop_transport::controls_allowed()
#endif
   ;
   unsigned steps=cadence.advance(microseconds(),held);
   if(steps&&!pilot_engine::apply(input,steps)){detail="native_player_model_or_pose_failed";stop(false);return;}
   detail=held?(gate.spectating?"guest_spectating":fresh?"host_paused":"waiting_fresh_guest_input"):(local?"local_test_input_drives_player":"steam_guest_input_drives_player");
#endif
   if(now-last_send>=33){
    ac8pilot::Frame f;f.flags=ac8pilot::flight_only|(paused()?ac8pilot::paused:0);f.generation=generation;f.revision=revision;f.source_us=microseconds();f.count=4;
#ifdef AC8_R27_EMBEDDED_PILOT
    if(gate.loaded)f.flags|=ac8pilot::loaded_ack;
#endif
    bool valid=true;for(unsigned i=0;i<4;++i)valid=pilot_engine::pose(i,f.poses[i])&&valid;
#ifdef AC8_OWNER_NATIVE_R31
    if(owner_receiver.have)f.poses[1].speed=owner_receiver.latest.poses[0].speed;
#endif
    if(valid){if(f.poses[1].health<=0){gate.died();f.flags|=ac8pilot::dead;}f.sender=ctx.local;f.session=ctx.nonce;f.echo=ctx.remote;f.sequence=++sequence;binary(L"guest-pilot-host-state.ac8p",f);send(f);last_send=now;}
   }
  }
 }
#ifdef AC8_OWNER_NATIVE_R31
 if(!is_host&&owner_pilot.running()){
  const bool held=paused()||!loaded_sent||!have_state||now<received_state_ms||now-received_state_ms>300||(latest.flags&(ac8pilot::paused|ac8pilot::dead))||!(latest.flags&ac8pilot::loaded_ack)||!owner_controls_allowed()||!local_input_at||now<local_input_at||now-local_input_at>100;
  owner_pilot.release(!held);
  if(!owner_pilot.tick(microseconds(),local_input,held,[](const ac8pilot::Frame&f){return send(f);})){detail=owner_pilot.detail;stop(false);return;}
  detail=held?"owner_model_held_by_barrier_or_pause":"guest_stock_model_simulates_locally";
 }
#endif
 if(now-last_report>=250)report();
}
bool guest_loaded(){
 if(is_host||!active||!have_state||GetTickCount64()-received_state_ms>1000)return false;
#ifdef AC8_OWNER_NATIVE_R31
 if(!owner_pilot.running()||!owner_backend.valid())return false;
#endif
 ac8pilot::Frame f;f.kind=ac8pilot::Kind::loaded;f.generation=latest.generation;f.revision=latest.revision;
 loaded_sent=send(f);return loaded_sent;
}
bool submit_capture(ac8pilot::Frame f);
bool guest_input(){
 if(is_host||!active||!have_state||!loaded_sent||GetTickCount64()-received_state_ms>300||(latest.flags&(ac8pilot::paused|ac8pilot::dead)))return false;
#ifdef AC8_R27_EMBEDDED_PILOT
 #ifdef AC8_OWNER_NATIVE_R31
 if(!(latest.flags&ac8pilot::loaded_ack)||!owner_controls_allowed())return false;
#else
 if(!(latest.flags&ac8pilot::loaded_ack)||!ac8coop_transport::controls_allowed())return false;
#endif
#endif
 std::map<std::string,std::string>r;uint64_t created=0;if(!pilot_engine::file(L"guest-pilot-input.tsv",r)||!pilot_engine::number(r["created_unix"],created)||std::llabs(int64_t(time(nullptr))-int64_t(created))>1)return false;
 ac8pilot::Frame f;f.kind=ac8pilot::Kind::input;f.generation=latest.generation;f.revision=latest.revision;
 unsigned i=0;for(auto key:{"pitch","roll","yaw","throttle","brake"}){const auto&s=r[key];errno=0;char*e=nullptr;const auto n=strtol(s.c_str(),&e,10);if(s.empty()||errno||e!=s.c_str()+s.size()||n<-32767||n>32767||(i>=3&&n<0))return false;f.axes[i++]=int16_t(n);}
 return submit_capture(f);
}
bool submit_capture(ac8pilot::Frame f){
#ifdef AC8_OWNER_NATIVE_R31
 const auto ctx=context();local_input=ac8pilot::input(f);local_input.sender=ctx.local;local_input.session=ctx.nonce;local_input.echo=ctx.remote;local_input.sequence=1;
 if(!ac8input::valid(local_input))return false;local_input_at=GetTickCount64();++accepted_inputs;return true;
#else
 return send(f);
#endif
}
bool capture_guest_input(){
 if(is_host||!active||!have_state||!loaded_sent||GetTickCount64()-received_state_ms>300||(latest.flags&(ac8pilot::paused|ac8pilot::dead)))return false;
#ifdef AC8_R27_EMBEDDED_PILOT
 #ifdef AC8_OWNER_NATIVE_R31
 if(!(latest.flags&ac8pilot::loaded_ack)||!owner_controls_allowed())return false;
#else
 if(!(latest.flags&ac8pilot::loaded_ack)||!ac8coop_transport::controls_allowed())return false;
#endif
#endif
 ac8pilot::RawInput raw;DWORD foreground=0;GetWindowThreadProcessId(GetForegroundWindow(),&foreground);raw.focused=foreground==GetCurrentProcessId();
 if(raw.focused){
  auto down=[](int key){return (GetAsyncKeyState(key)&0x8000)!=0;};raw.up=down(VK_UP);raw.down=down(VK_DOWN);raw.left=down(VK_LEFT);raw.right=down(VK_RIGHT);
  raw.yaw_left=down('Q');raw.yaw_right=down('E');raw.throttle=down('W');raw.brake=down('S');
  static HMODULE xinput=LoadLibraryExW(L"xinput1_4.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);
  using GetPad=DWORD(WINAPI*)(DWORD,XINPUT_STATE*);static auto get=xinput?reinterpret_cast<GetPad>(GetProcAddress(xinput,"XInputGetState")):nullptr;
  if(get){for(DWORD i=0;i<4;++i){XINPUT_STATE pad{};if(get(i,&pad)==ERROR_SUCCESS){raw.stick_x=pad.Gamepad.sThumbLX;raw.stick_y=pad.Gamepad.sThumbLY;raw.trigger_left=pad.Gamepad.bLeftTrigger;raw.trigger_right=pad.Gamepad.bRightTrigger;raw.pad_left=(pad.Gamepad.wButtons&XINPUT_GAMEPAD_LEFT_SHOULDER)!=0;raw.pad_right=(pad.Gamepad.wButtons&XINPUT_GAMEPAD_RIGHT_SHOULDER)!=0;break;}}}
 }
 ac8pilot::Frame f;f.kind=ac8pilot::Kind::input;f.generation=latest.generation;f.revision=latest.revision;f.axes=ac8pilot::axes(raw);return submit_capture(f);
}
int dispatch(unsigned action){
 if(!setup())return 0;
 if(action==0){if(!start()){detail="pilot_start_refused";report();}}
 if(action==1)tick();
 if(action==2)stop(true);
 if(action==3){detail=guest_loaded()?"guest_world_loaded_sent":"guest_world_loaded_refused";report();}
 if(action==4){guest_input();}
 if(action==5){capture_guest_input();}
#ifdef AC8_OWNER_NATIVE_R31
 if(action==7){
  // Local lab only: evaluate dependencies without allocating an actor. Missing
  // managers may finish loading; retry stays bounded by the Lua coordinator.
  if(active&&local&&!is_host&&!owner_backend.configured&&!owner_backend.ledger.attempted&&have_state){
   owner_backend.configure_request(owner_local_request,generation,revision,context());
  }
  report();
 }
 if(action==8){
  FILE*f=nullptr;if(!_wfopen_s(&f,(pilot_engine::directory+L"\\owner-lab-clock.tsv").c_str(),L"wb")&&f){fprintf(f,"monotonic_ms\t%llu\n",GetTickCount64());fclose(f);}
 }
 if(action==9){
  wchar_t marker[32]{};std::map<std::string,std::string>r;uint64_t created=0,pointer=0;
  if(!active&&env(L"AC8_OWNER_LOCAL_LAB",marker,32)&&!wcscmp(marker,L"25201480")&&
   pilot_engine::file(L"guest-owner-camera.tsv",r)&&pilot_engine::number(r["created_unix"],created)&&
   std::llabs(int64_t(time(nullptr))-int64_t(created))<=3&&pilot_engine::number(r["camera"],pointer)){
   detail=owner_backend.track_camera(pointer)?"local_camera_receipt_captured":owner_backend.reason();
  }else detail="local_camera_receipt_refused";
  report();
 }
 if(action==10){
  wchar_t marker[32]{};std::map<std::string,std::string>r;uint64_t created=0,cl=0,cd=0;
  if(!active&&env(L"AC8_OWNER_LOCAL_LAB",marker,32)&&!wcscmp(marker,L"25201480")&&
     pilot_engine::file(L"guest-owner-template.tsv",r)&&pilot_engine::number(r["created_unix"],created)&&
     std::llabs(int64_t(time(nullptr))-int64_t(created))<=3&&pilot_engine::number(r["owner_class"],cl)&&pilot_engine::number(r["owner_cdo"],cd)){
   detail=owner_backend.retain_template(cl,cd)?"local_template_retained":owner_backend.reason();
  }else detail="local_template_retain_refused";
  report();
 }
 if(action==6){
  if(active&&!is_host&&have_state&&!owner_pilot.running()){
   const auto ctx=context();const bool configured=!local||owner_backend.configured||owner_backend.configure_request(owner_local_request,generation,revision,ctx);
   const bool ok=configured&&owner_backend.read_seed(latest)&&owner_pilot.prepare({ctx.remote,generation,revision},ctx);
   detail=ok?"owner_stock_model_prepared_wait_loaded_ack":owner_backend.reason();if(!ok)active=false;
  }
  report();
 }
#endif
 return 0;
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_start(void*){return pilot_bridge::dispatch(0);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_tick(void*){return pilot_bridge::dispatch(1);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_stop(void*){return pilot_bridge::dispatch(2);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_loaded(void*){return pilot_bridge::dispatch(3);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_input(void*){return pilot_bridge::dispatch(4);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_capture_input(void*){return pilot_bridge::dispatch(5);}
#ifdef AC8_OWNER_NATIVE_R31
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_prepare(void*){return pilot_bridge::dispatch(6);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_preflight(void*){return pilot_bridge::dispatch(7);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_track_camera(void*){return pilot_bridge::dispatch(9);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_retain_template(void*){return pilot_bridge::dispatch(10);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_pilot_clock(void*){return pilot_bridge::dispatch(8);}
#endif
