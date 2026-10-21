// Socket access stays on the room worker; UObject/model work stays on GT.
#include "steam_coop_clock.h"
#include "coop_skip_input.h"
#ifdef AC8_SESSION_POLICY_R29
#include "session_policy.h"
static ac8session::Watchdog session_watchdog;
#endif
#ifdef AC8_CINEMA_SYNC_R28
#include "cinema_channel.inl"
#endif
namespace coop27 {
struct Published {ac8pilot::Context context{};uint32_t phase=0,generation=0,revision=0,scene=0,epoch=0;uint64_t at=0,token=0;bool flight_phase=false;};
static SRWLOCK lock=SRWLOCK_INIT;
static Published published;
static std::deque<ac8pilot::Frame> outbound;
static std::deque<std::pair<ac8pilot::Frame,uint64_t>> inbound;
static ac8coop::Clock clock;
static uint64_t clock_sent=0,bound_remote=0;
static std::string visual_transfer;static uint64_t visual_sequence=0,visual_generation=0,visual_published=0;static size_t visual_part=0;
static bool send_session(ac8session::Frame f){
 if(!connected||!session.ready()||session_v2_tx==UINT64_MAX)return false;
 f.sender=local_id;f.session=session.nonce;f.echo=session.remote;f.sequence=session_v2_tx+1;
 if(!ac8session::valid(f))return false;const auto b=ac8session::encode(f);
 if(api.send(api.sockets,connection,b.data(),uint32(b.size()),k_nSteamNetworkingSend_ReliableNoNagle,nullptr)!=k_EResultOK)return false;
 session_v2_tx=f.sequence;return true;
}
static bool clock_frame(const ac8session::Frame&f){
 if(f.kind!=ac8session::Kind::intent)return false;
 const auto now=GetTickCount64();
 if(role==Role::host&&f.op==ac8session::Op::clock_ping){
  ac8session::Frame reply;reply.op=ac8session::Op::clock_reply;reply.args[0]=f.args[0];reply.args[1]=f.args[1];reply.args[2]=uint32_t(now);reply.args[3]=uint32_t(now>>32);return send_session(reply);
 }
 if(role==Role::guest&&f.op==ac8session::Op::clock_reply){
  clock.accept(uint64_t(f.args[0])|(uint64_t(f.args[1])<<32),uint64_t(f.args[2])|(uint64_t(f.args[3])<<32),now);return true;
 }return false;
}
static Published view(){AcquireSRWLockShared(&lock);auto p=published;ReleaseSRWLockShared(&lock);return p;}
static void reset(){AcquireSRWLockExclusive(&lock);published={};outbound.clear();inbound.clear();ReleaseSRWLockExclusive(&lock);clock.reset();clock_sent=bound_remote=0;visual_transfer.clear();visual_sequence=visual_generation=visual_published=0;visual_part=0;scene_assembler={};scene_pending.clear();scene_rx=scene_tx=0;
#ifdef AC8_SESSION_POLICY_R29
 session_watchdog={};
#endif
#ifdef AC8_CINEMA_SYNC_R28
 coop28::reset();
#endif
}
static void scene_files(const wchar_t*folder){
 if(role==Role::guest){
  if(scene_pending.empty())return;std::string payload=std::move(scene_pending.back());scene_pending.clear();
  const auto temp=std::wstring(folder)+L"\\scene-client.ac8w.tmp",path=std::wstring(folder)+L"\\scene-client.ac8w";
  FILE*f=_wfsopen(temp.c_str(),L"wb",_SH_DENYWR);if(!f)return;const auto n=fwrite(payload.data(),1,payload.size(),f);fclose(f);
  if(n==payload.size())MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);return;
 }
 if(visual_transfer.empty()){
  FILE*f=_wfsopen((std::wstring(folder)+L"\\scene-host.ac8w").c_str(),L"rb",_SH_DENYNO);if(!f)return;
  std::string data(ac8scene::max_bytes+1,'\0');auto n=fread(data.data(),1,data.size(),f);fclose(f);data.resize(n);
  constexpr char prefix[]="AC8W\t2\t25201480\nframe\t";unsigned long long seq=0,gen=0;
  if(n>ac8scene::max_bytes||n<sizeof(prefix)||data.compare(0,sizeof(prefix)-1,prefix)||data.back()!='\n'||sscanf_s(data.c_str()+sizeof(prefix)-1,"%llu\t%llu",&seq,&gen)!=2||!gen||seq<=visual_published)return;
  visual_sequence=seq;visual_generation=gen;visual_part=0;visual_transfer=std::move(data);
 }
 // One bounded chunk per worker turn keeps room/clock/input traffic ahead of
 // visual baselines. Never mix partial transfers or evaluate received text.
 const size_t count=(visual_transfer.size()+ac8scene::chunk_size-1)/ac8scene::chunk_size;
 if(scene_tx==UINT64_MAX){connection_ended("scene_sequence_exhausted");return;}
 ac8scene::Chunk chunk;chunk.sender=local_id;chunk.session=session.nonce;chunk.echo=session.remote;chunk.sequence=++scene_tx;chunk.generation=visual_generation;chunk.transfer=visual_sequence;chunk.index=uint32_t(visual_part);chunk.count=uint32_t(count);chunk.total=uint32_t(visual_transfer.size());chunk.data=visual_transfer.substr(visual_part*ac8scene::chunk_size,ac8scene::chunk_size);
 auto encoded=ac8scene::encode(chunk);
 if(api.send(api.sockets,connection,encoded.data(),uint32(encoded.size()),k_nSteamNetworkingSend_ReliableNoNagle,nullptr)!=k_EResultOK){connection_ended("scene_send_failed");return;}
 if(++visual_part==count){visual_published=visual_sequence;visual_transfer.clear();}
}
static void worker(ac8session::State&authority,const wchar_t*folder,uint64_t token){
 const auto now=GetTickCount64();const bool ready=connected&&session.ready();
 const auto remote=ready?session.remote:0;
 if(remote!=bound_remote){reset();bound_remote=remote;pilot_pending.clear();pilot_rx=pilot_tx=0;}
 if(ready&&role==Role::guest&&now-clock_sent>=750){
  ac8session::Frame f;f.op=ac8session::Op::clock_ping;f.args[0]=uint32_t(now);f.args[1]=uint32_t(now>>32);
  if(send_session(f)){clock.begin(now);clock_sent=now;}
 }
 if(ready&&role==Role::host)authority.tick(now);
#ifdef AC8_SESSION_POLICY_R29
 if(ready&&role==Role::host)session_watchdog.tick(authority,now);
 lobby_join_open=authority.accepts_join();
#endif
 // Both commits must be observed before a guest can release on its calibrated
 // deadline. Otherwise the authoritative host snapshot remains necessary.
#ifndef AC8_CINEMA_SYNC_R28
 if(ready&&role==Role::guest&&clock.ready(now)&&authority.committed==3)authority.tick(clock.host_now(now));
#endif
#ifdef AC8_CINEMA_SYNC_R28
 if(ready){
  coop28::files(authority,folder,token,now);
  if(role==Role::host)authority.cinema_tick(now);
  // Do not mutate the guest's authoritative snapshot speculatively: an older
  // in-flight host snapshot would otherwise appear to rewind its changes.
 }
#endif
 Published next;next.at=now;next.phase=uint32_t(authority.stage);next.generation=authority.generation;next.revision=authority.revision;next.scene=authority.scene;next.epoch=authority.epoch;next.token=token;
 next.flight_phase=authority.stage==ac8session::Stage::flight_loading||authority.stage==ac8session::Stage::flight||(authority.stage==ac8session::Stage::cutscene&&authority.scene_return==6);
 if(ready)next.context={local_id,peer_id,session.nonce,session.remote,role==Role::host};
 std::deque<ac8pilot::Frame> sending;
 AcquireSRWLockExclusive(&lock);published=next;
 if(!ready||!next.flight_phase){outbound.clear();inbound.clear();pilot_pending.clear();}
 else{
  while(!pilot_pending.empty()){
   auto item=pilot_pending.front();pilot_pending.pop_front();
   if(item.first.generation!=next.generation||item.first.revision!=next.revision)continue;
   if(inbound.size()>=64)inbound.pop_front();inbound.push_back(item);
  }
  sending.swap(outbound);
 }
 ReleaseSRWLockExclusive(&lock);
 for(auto&f:sending)if(f.generation==next.generation&&f.revision==next.revision)ac8pilot_transport::send(f);
 if(ready&&authority.stage!=ac8session::Stage::lobby&&authority.stage!=ac8session::Stage::stopped)scene_files(folder);
}
static void status(FILE*f,const ac8session::State&s){
 auto now=GetTickCount64();const bool calibrated=role==Role::host||clock.ready(now);
 fprintf(f,"mission_sync\t1\nprotocol\t%u\nscene\t%u\nscene_exit\t%u\nscene_return\t%u\nloaded_mask\t%u\nvote_mask\t%u\ncommit_mask\t%u\nrelease_at\t%llu\ngeneration\t%u\nlocal_tick\t%llu\nhost_tick\t%llu\nclock_ready\t%d\nclock_rtt\t%llu\nhangar_scene_supported\t1\n",ac8session::protocol_version,s.scene,s.scene_exit,s.scene_return,s.loaded,s.votes,s.committed,static_cast<unsigned long long>(s.release_at),s.generation,static_cast<unsigned long long>(now),static_cast<unsigned long long>(role==Role::host?now:clock.host_now(now)),calibrated?1:0,static_cast<unsigned long long>(clock.rtt));
#ifdef AC8_CINEMA_SYNC_R28
 fprintf(f,"cinema_sync\t1\ncinema_prepared\t%u\ncinema_finished\t%u\ncinema_state\t%u\ncinema_commit_mask\t%u\ncinema_at\t%llu\n",s.cinema_prepared,s.cinema_finished,s.cinema_state,s.cinema_committed,static_cast<unsigned long long>(s.cinema_at));
#ifdef AC8_SESSION_POLICY_R29
 fprintf(f,"session_policy\t1\nhost_progress_only\t1\njoin_open\t%d\nstop_reason\t%u\nrestart_id\t%u\nrestart_ack\t%u\nloading_timeout_ms\t120000\nloading_remaining_ms\t%llu\n",s.accepts_join()?1:0,uint32_t(s.stop_reason),s.restart_id,s.restart_ack,static_cast<unsigned long long>(session_watchdog.remaining(now)));
#endif
#endif
}
static void capture_vote(){
 static ac8coop::SkipHold hold;static uint64_t nonce=0,serial=0;static DWORD owner=0;
 if(!owner)owner=GetCurrentThreadId();if(owner!=GetCurrentThreadId())return;
 const auto p=view();if(p.context.nonce!=nonce){hold={};nonce=p.context.nonce;}
 DWORD focused=0;GetWindowThreadProcessId(GetForegroundWindow(),&focused);
 const bool down=(GetAsyncKeyState(VK_ESCAPE)&0x8000)!=0;
 if(!hold.sample(GetTickCount64(),focused==GetCurrentProcessId()&&!p.context.host&&p.context.peer&&GetTickCount64()-p.at<=1000,down,p.phase,p.scene))return;
 wchar_t folder[32768]{};const auto n=GetEnvironmentVariableW(L"AC8_COOP_RECON_OUTPUT",folder,32768);if(!n||n>=32768)return;
 FILE*f=_wfsopen((std::wstring(folder)+L"\\guest-skip-input.tsv").c_str(),L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"sequence\t%llu\nconfig_token\t%llu\nepoch\t%u\nscene\t%u\n",static_cast<unsigned long long>(++serial),static_cast<unsigned long long>(p.token),p.epoch,p.scene);fclose(f);
}
}
namespace ac8coop_transport {
ac8pilot::Context context(){const auto p=coop27::view();return p.flight_phase&&GetTickCount64()-p.at<=1000?p.context:ac8pilot::Context{};}
bool controls_allowed(){const auto p=coop27::view();return p.phase==6&&p.context.peer&&GetTickCount64()-p.at<=1000;}
bool session_matches(uint64_t generation,uint32_t revision){const auto p=coop27::view();return p.flight_phase&&p.context.peer&&p.generation==generation&&p.revision==revision&&GetTickCount64()-p.at<=1000;}
bool send(ac8pilot::Frame f){
 const auto p=coop27::view();if(!p.flight_phase||!p.context.peer||p.generation!=f.generation||p.revision!=f.revision||GetTickCount64()-p.at>1000)return false;
 AcquireSRWLockExclusive(&coop27::lock);
 // Replace unsent continuous state/input, but retain loaded/stop barriers.
 if(f.kind==ac8pilot::Kind::input||f.kind==ac8pilot::Kind::state){
  for(auto i=coop27::outbound.begin();i!=coop27::outbound.end();)if(i->kind==f.kind)i=coop27::outbound.erase(i);else ++i;
 }
 const auto&current=coop27::published;
 bool ok=current.context.peer==p.context.peer&&current.context.nonce==p.context.nonce&&current.context.remote==p.context.remote&&current.flight_phase&&current.generation==f.generation&&current.revision==f.revision&&coop27::outbound.size()<64;
 if(ok)coop27::outbound.push_back(f);ReleaseSRWLockExclusive(&coop27::lock);return ok;
}
bool take(ac8pilot::Frame&f,uint64_t&at){
 AcquireSRWLockExclusive(&coop27::lock);const bool ok=!coop27::inbound.empty();
 if(ok){f=coop27::inbound.front().first;at=coop27::inbound.front().second;coop27::inbound.pop_front();}
 ReleaseSRWLockExclusive(&coop27::lock);return ok;
}
}
