// Steam room only: no NetDriver, travel, game actors or mission callbacks.
#ifndef AC8_R24_BASE_INCLUDED
#define AC8_STEAM_LOBBY_R24
#define AC8_SESSION_TRANSPORT
#include "connection_test.cpp"
#endif
#include <atomic>
#include <string>
namespace lobby24 {
static HANDLE worker=nullptr;
static bool configured_host=false;
static std::atomic<bool> stopping{false};
static ac8session::State authority;
static bool have_snapshot=false,was_ready=false;
static uint64_t config_token=0,request_seen=0,confirmed=0,pending_wire=0,pending_request=0,guest_ack=0;
static uint32_t reject_code=0,guest_reject=0;
static uint64_t bound_nonce24=0;
static wchar_t control_dir[32768]{};
static void update_binding(){
 const bool ready=connected&&session.ready();
 if(was_ready&&(!ready||bound_nonce24!=session.remote)){
  authority.disconnect();authority.planes[1]={};have_snapshot=false;guest_ack=guest_reject=0;pending_wire=pending_request=0;
 }
 was_ready=ready;bound_nonce24=ready?session.remote:0;
}
static bool decimal24(const std::string&s,uint64_t&v,uint64_t maximum){
 if(s.empty()||s.size()>20)return false;v=0;
 for(char c:s){if(c<'0'||c>'9')return false;auto d=static_cast<unsigned>(c-'0');if(d>maximum||v>(maximum-d)/10)return false;v=v*10+d;}return true;
}
static bool send(ac8session::Frame f,uint64_t*sequence=nullptr){
 if(!connected||!session.ready()||session_v2_tx==UINT64_MAX)return false;
 f.sender=local_id;f.session=session.nonce;f.echo=session.remote;f.sequence=session_v2_tx+1;
 if(!ac8session::valid(f))return false;auto bytes=ac8session::encode(f);
 if(api.send(api.sockets,connection,bytes.data(),static_cast<uint32>(bytes.size()),k_nSteamNetworkingSend_ReliableNoNagle,nullptr)!=k_EResultOK)return false;
 session_v2_tx=f.sequence;if(sequence)*sequence=f.sequence;return true;
}
static bool consume(const ac8session::Frame&f){
 update_binding();
#ifdef AC8_STEAM_COOP_R27
 if(f.op==ac8session::Op::clock_ping||f.op==ac8session::Op::clock_reply)return coop27::clock_frame(f);
#endif
 if(role==Role::host){
#ifndef AC8_STEAM_COOP_R27
  if(f.kind!=ac8session::Kind::intent||(f.op!=ac8session::Op::ready&&f.op!=ac8session::Op::loadout))return false;
#else
  if(f.kind!=ac8session::Kind::intent)return false;
  if(f.op!=ac8session::Op::ready&&f.op!=ac8session::Op::loadout&&f.op!=ac8session::Op::loaded&&f.op!=ac8session::Op::vote_skip&&f.op!=ac8session::Op::commit
#ifdef AC8_CINEMA_SYNC_R28
   &&f.op!=ac8session::Op::cinema_prepared&&f.op!=ac8session::Op::cinema_finished&&f.op!=ac8session::Op::cinema_commit
#ifdef AC8_SESSION_POLICY_R29
   &&f.op!=ac8session::Op::cancel&&f.op!=ac8session::Op::fault&&f.op!=ac8session::Op::restart_ack
#endif
#endif
  ){guest_reject=1;guest_ack=f.sequence;return true;}
#endif
  guest_reject=static_cast<uint32_t>(authority.apply(1,f.op,f.args,f.epoch,f.revision));guest_ack=f.sequence;
  log(guest_reject?"lobby24_guest_rejected":"lobby24_guest_applied",guest_reject);return true;
 }
 if(f.kind!=ac8session::Kind::snapshot)return false;ac8session::State next;
 if(!ac8session::state_from(f,next))return false;
 if(have_snapshot&&(next.epoch<authority.epoch||next.revision<authority.revision||next.changes<authority.changes))return false;
 authority=next;have_snapshot=true;
 const uint64_t ack=uint64_t(f.args[36])|(uint64_t(f.args[37])<<32);
 if(pending_wire&&ack>=pending_wire){confirmed=pending_request;reject_code=f.args[38];pending_wire=pending_request=0;}
 return true;
}
static std::string caption(const char*value){
 std::string result;if(!value)return result;
 for(size_t i=0;i<512&&value[i];++i){const auto c=static_cast<unsigned char>(value[i]);if(c>=32&&c!=127)result.push_back(static_cast<char>(c));}
 // Do not cut a UTF-8 sequence at the bounded end.
 if(result.size()>=512){while(!result.empty()&&(static_cast<unsigned char>(result.back())&0xc0)==0x80)result.pop_back();if(!result.empty()&&static_cast<unsigned char>(result.back())>=0xc0)result.pop_back();}
 return result;
}
static void snapshot_status(){
 wchar_t path[32768]{},temp[32768]{};
 if(swprintf_s(path,L"%ls\\shared-session-status.tsv",control_dir)<0||swprintf_s(temp,L"%ls\\shared-session-status.tmp",control_dir)<0)return;
 FILE*f=_wfsopen(temp,L"w",_SH_DENYWR);if(!f)return;const bool ready=connected&&session.ready();
 std::string own,other;
 if(lobby_friends24.handle){if(lobby_friends24.persona)own=caption(lobby_friends24.persona(lobby_friends24.handle));if(peer_id&&lobby_friends24.friend_persona)other=caption(lobby_friends24.friend_persona(lobby_friends24.handle,peer_id));}
 fprintf(f,"format\tac8-session-status-v3\nconfig_token\t%llu\nconnected\t%d\nhave_snapshot\t%d\nrole\t%s\nself\t%llu\npeer\t%llu\nrequest_ack\t%llu\nrequest_confirmed\t%llu\nreject\t%u\ntransport\t%s\nreason\t%s\nphase\t%u\nepoch\t%u\nrevision\t%u\nmission\t%u\ndifficulty\t%u\nready_mask\t%u\nchanges\t%u\nhost_aircraft\t%u\nguest_aircraft\t%u\nguest_weapon1\t%u\nguest_weapon2\t%u\nhost_name\t%s\nguest_name\t%s\nfull_mission_replication\t0\n",
 config_token,ready?1:0,(role==Role::host||have_snapshot)?1:0,role==Role::host?"host":"guest",local_id,peer_id,request_seen,role==Role::host?request_seen:confirmed,reject_code,state,reason,static_cast<uint32_t>(authority.stage),authority.epoch,authority.revision,authority.mission,authority.difficulty,authority.ready,authority.changes,authority.planes[0].aircraft,authority.planes[1].aircraft,authority.planes[1].weapon1,authority.planes[1].weapon2,role==Role::host?own.c_str():other.c_str(),role==Role::host?other.c_str():own.c_str());
#ifdef AC8_STEAM_COOP_R27
 coop27::status(f,authority);
#endif
 fprintf(f,"heartbeat\t%llu\n",GetTickCount64());fclose(f);MoveFileExW(temp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
#ifdef AC8_SESSION_POLICY_R29
static void read_emergency(){
 FILE*f=_wfsopen((std::wstring(control_dir)+L"\\session-emergency.tsv").c_str(),L"rb",_SH_DENYNO);if(!f)return;
 char bytes[513]{};const auto n=fread(bytes,1,sizeof(bytes),f);fclose(f);if(!n||n>512)return;std::string text(bytes,n);
 const char*keys[]={"request","config_token","epoch","revision","op","generation"};uint64_t a[6]{};size_t pos=0;
 for(size_t i=0;i<6;++i){const auto end=text.find('\n',pos);if(end==std::string::npos)return;auto line=text.substr(pos,end-pos);pos=end+1;auto tab=line.find('\t');if(tab==std::string::npos||line.substr(0,tab)!=keys[i]||!decimal24(line.substr(tab+1),a[i],i<2?0x1fffffffffffffull:UINT32_MAX))return;}
 if(pos!=text.size()||!a[0]||a[0]<=request_seen||a[1]!=config_token||(a[4]!=23&&a[4]!=24))return;
 ac8session::Args args{};args[0]=uint32_t(a[5]);const auto op=static_cast<ac8session::Op>(a[4]);
 if(role==Role::host){reject_code=uint32_t(authority.apply(0,op,args,uint32_t(a[2]),uint32_t(a[3])));request_seen=confirmed=a[0];}
 else if(connected&&session.ready()&&have_snapshot){
  ac8session::Frame frame;frame.op=op;frame.args=args;frame.epoch=uint32_t(a[2]);frame.revision=uint32_t(a[3]);uint64_t sent=0;
  // Cancel supersedes a stalled ordinary intent. An older ACK cannot confirm it.
  if(send(frame,&sent)){pending_wire=sent;pending_request=request_seen=a[0];reject_code=0;}
 }
}
#endif
static void read_request(){
 wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\shared-session-command.tsv",control_dir)<0)return;FILE*f=_wfsopen(path,L"rb",_SH_DENYNO);if(!f)return;
 char buffer[4097]{};auto n=fread(buffer,1,sizeof(buffer),f);fclose(f);if(!n||n>4096)return;std::string text(buffer,n);if(text.find('\0')!=std::string::npos)return;
 const char*keys[]={"request","epoch","revision","op","arg0","arg1"};uint64_t values[6]{};size_t position=0;
 for(size_t i=0;i<6;++i){auto end=text.find('\n',position);if(end==std::string::npos)return;auto line=text.substr(position,end-position);position=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos||line.substr(0,tab)!=keys[i]||!decimal24(line.substr(tab+1),values[i],i?UINT32_MAX:0x1fffffffffffffull))return;}
 if(position!=text.size()||!values[0]||values[0]<=request_seen)return;
 const auto op=static_cast<ac8session::Op>(values[3]);ac8session::Args args{};args[0]=static_cast<uint32_t>(values[4]);args[1]=static_cast<uint32_t>(values[5]);
#ifdef AC8_STEAM_COOP_R27
#ifdef AC8_SESSION_POLICY_R29
 if(values[3]<1||values[3]>27||values[3]==17||values[3]==18)
#elif defined(AC8_CINEMA_SYNC_R28)
 if(values[3]<1||values[3]>21||values[3]==17||values[3]==18)
#else
 if(values[3]<1||values[3]>16)
#endif
 {request_seen=confirmed=values[0];reject_code=2;return;}
 if((op==ac8session::Op::commit
#ifdef AC8_CINEMA_SYNC_R28
 ||op==ac8session::Op::cinema_commit
#endif
 )&&role==Role::guest&&!coop27::clock.ready(GetTickCount64())){request_seen=confirmed=values[0];reject_code=5;return;}
#else
 if(op!=ac8session::Op::ready&&op!=ac8session::Op::select_mission&&op!=ac8session::Op::loadout){request_seen=values[0];reject_code=2;return;}
#endif
 if(role==Role::host){
  if(op==ac8session::Op::ready&&(!connected||!session.ready()))return;
#ifdef AC8_SESSION_POLICY_R29
  if(op==ac8session::Op::restart&&(!connected||!session.ready())){request_seen=values[0];reject_code=5;return;}
#endif
  reject_code=static_cast<uint32_t>(authority.apply(0,op,args,static_cast<uint32_t>(values[1]),static_cast<uint32_t>(values[2])));request_seen=values[0];
  log(reject_code?"lobby24_host_rejected":"lobby24_host_applied",reject_code);
 }else{
  if(!connected||!session.ready()||!have_snapshot||pending_wire)return;
  if(op!=ac8session::Op::ready&&op!=ac8session::Op::loadout
#ifdef AC8_STEAM_COOP_R27
   &&op!=ac8session::Op::loaded&&op!=ac8session::Op::vote_skip&&op!=ac8session::Op::commit
#ifdef AC8_CINEMA_SYNC_R28
   &&op!=ac8session::Op::cinema_prepared&&op!=ac8session::Op::cinema_finished&&op!=ac8session::Op::cinema_commit
#ifdef AC8_SESSION_POLICY_R29
   &&op!=ac8session::Op::cancel&&op!=ac8session::Op::fault&&op!=ac8session::Op::restart_ack
#endif
#endif
#endif
  ){request_seen=confirmed=values[0];reject_code=1;return;}
  ac8session::Frame frame;frame.kind=ac8session::Kind::intent;frame.op=op;frame.args=args;frame.epoch=static_cast<uint32_t>(values[1]);frame.revision=static_cast<uint32_t>(values[2]);
  uint64_t sent=0;if(send(frame,&sent)){pending_wire=sent;pending_request=request_seen=values[0];reject_code=0;}
 }
}
static DWORD WINAPI run(void*){
 boundary(1);uint64_t published=0,last_snapshot=0,status_written_at24=0,last_guest_ack=0,retry_at24=GetTickCount64();
 while(!stopping&&!faulted){
  if(!initialized&&GetTickCount64()-retry_at24>=1000){boundary(1);retry_at24=GetTickCount64();}
  boundary(0);const bool ready=connected&&session.ready();
  update_binding();
#ifdef AC8_SESSION_POLICY_R29
  read_emergency();
#endif
  read_request();const auto now=GetTickCount64();
#ifdef AC8_STEAM_COOP_R27
  coop27::worker(authority,control_dir,config_token);
#endif
  if(ready&&role==Role::host&&(published!=authority.changes||last_guest_ack!=guest_ack||now-last_snapshot>=300)){
   auto frame=ac8session::snapshot(authority);frame.args[36]=static_cast<uint32_t>(guest_ack);frame.args[37]=static_cast<uint32_t>(guest_ack>>32);frame.args[38]=guest_reject;
   if(send(frame)){published=authority.changes;last_guest_ack=guest_ack;last_snapshot=now;}
  }
  if(now-status_written_at24>=100){snapshot_status();status_written_at24=now;}Sleep(20);
 }
 boundary(2);
#ifdef AC8_STEAM_COOP_R27
 coop27::reset();
#endif
 snapshot_status();return 0;
}
static bool configure(){
 wchar_t marker[32]{},steam_path[32768]{},path[32768]{};
 if(!read_env(L"AC8_STEAM_LOBBY",marker,32)||wcscmp(marker,L"25201480")||!read_env(L"AC8_COOP_RECON_OUTPUT",control_dir,32768)||!read_env(L"AC8_SHARED_STEAM_DLL",steam_path,32768))return false;
 if(swprintf_s(path,L"%ls\\shared-session-config.tsv",control_dir)<0)return false;FILE*f=_wfsopen(path,L"rb",_SH_DENYNO);if(!f)return false;
 char bytes[129]{};auto n=fread(bytes,1,sizeof(bytes),f);fclose(f);if(!n||n>128)return false;std::string config(bytes,n);if(config.find('\0')!=std::string::npos)return false;
 const auto first=config.find('\n'),second=config.find('\n',first==std::string::npos?0:first+1);if(first==std::string::npos||second==std::string::npos)return false;
 const auto selected=config.substr(0,first),peer=config.substr(first+1,second-first-1);auto token=config.substr(second+1);if(!token.empty()&&token.back()=='\n')token.pop_back();
 if((selected!="host"&&selected!="guest")||!decimal24(token,config_token,0x1fffffffffffffull)||!config_token)return false;
 std::wstring wide(peer.begin(),peer.end());uint64_t id=0;if(!(selected=="host"&&peer=="0")&&!id_from_text(wide.c_str(),id))return false;
 SetEnvironmentVariableW(L"AC8_CONNECTION_TEST",L"25201480");SetEnvironmentVariableW(L"AC8_CONNECTION_OUTPUT",control_dir);SetEnvironmentVariableW(L"AC8_CONNECTION_STEAM_DLL",steam_path);SetEnvironmentVariableW(L"AC8_CONNECTION_ROLE",selected=="host"?L"host":L"guest");SetEnvironmentVariableW(L"AC8_CONNECTION_PEER",wide.c_str());
 #ifdef AC8_SESSION_POLICY_R29
 wchar_t launch_role[16]{};if(!read_env(L"AC8_LOBBY_ROLE",launch_role,16)||(wcscmp(launch_role,L"host")&&wcscmp(launch_role,L"guest"))||((selected=="host")!=(!wcscmp(launch_role,L"host"))))return false;
 lobby_join_open=true;
#endif
 configured_host=selected=="host";
 initialized=false;authority={};have_snapshot=was_ready=false;bound_nonce24=0;request_seen=confirmed=pending_wire=pending_request=guest_ack=0;reject_code=guest_reject=0;session_v2_rx=session_v2_tx=0;stopping=false;
#ifdef AC8_STEAM_COOP_R27
 coop27::reset();
#endif
 AcquireSRWLockExclusive(&queue_lock);queue_size=0;queue_overflow=false;ReleaseSRWLockExclusive(&queue_lock);
 if(swprintf_s(path,L"%ls\\shared-session-command.tsv",control_dir)<0)return false;DeleteFileW(path);
 worker=CreateThread(nullptr,0,run,nullptr,0,nullptr);return worker!=nullptr;
}
static void control_status(){
 wchar_t folder[32768]{},path[32768]{},temp[32768]{};if(!read_env(L"AC8_COOP_RECON_OUTPUT",folder,32768))return;
 const bool running=worker&&WaitForSingleObject(worker,0)!=WAIT_OBJECT_0;
 if(worker&&!running){CloseHandle(worker);worker=nullptr;}
 if(swprintf_s(path,L"%ls\\shared-session-control.tsv",folder)<0||swprintf_s(temp,L"%ls\\shared-session-control.tmp",folder)<0)return;FILE*f=_wfsopen(temp,L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"format\tac8-steam-control-v1\nconfig_token\t%llu\nrunning\t%d\ncan_restart\t%d\n",config_token,running?1:0,(!running&&!faulted)?1:0);fclose(f);MoveFileExW(temp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
}
static bool consume_session_frame(const ac8session::Frame&frame){return lobby24::consume(frame);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_lobby24_start(void*){
 lobby24::control_status();if(!lobby24::worker&&!faulted)lobby24::configure();lobby24::control_status();return 0;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_lobby24_stop(void*){lobby24::stopping=true;return 0;}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_lobby24_tick(void*){lobby24::control_status();return 0;}
#ifdef AC8_STEAM_INVITES_R25
#include "steam_invites.inl"
#endif
