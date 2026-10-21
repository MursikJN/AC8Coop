#ifndef AC8_SESSION_BASE_INCLUDED
#define AC8_SESSION_TRANSPORT
#include "connection_test.cpp"
#endif
#include <atomic>
#include <string>
// All SDK/authority work belongs to this worker, never to Lua or a loading game thread.
static HANDLE worker=nullptr;static std::atomic<bool> worker_stop{false};
static ac8session::State authority;
static bool have_snapshot=false,was_ready=false;
static uint64_t request_seen=0,snapshot_sent_at=0,config_token=0;
static uint32_t reject_code=0;
static bool send_session(ac8session::Frame f){
 if(!connected||!session.ready()||session_v2_tx==UINT64_MAX)return false;
 f.sender=local_id;f.session=session.nonce;f.echo=session.remote;f.sequence=++session_v2_tx;
 if(!ac8session::valid(f))return false;const auto bytes=ac8session::encode(f);
 return api.send(api.sockets,connection,bytes.data(),static_cast<uint32>(bytes.size()),k_nSteamNetworkingSend_ReliableNoNagle,nullptr)==k_EResultOK;
}
static bool consume_session_frame(const ac8session::Frame&f){
 if(role==Role::host){
  if(f.kind!=ac8session::Kind::intent)return false;
  // Internal adapter-only operations are not network guest capabilities in this milestone.
  if(f.op==ac8session::Op::begin_intro||f.op==ac8session::Op::scene_ended)return false;
  reject_code=static_cast<uint32_t>(authority.apply(1,f.op,f.args,f.epoch,f.revision));
  log(reject_code?"guest_intent_rejected":"guest_intent_applied",reject_code);
  return true;
 }
 if(f.kind!=ac8session::Kind::snapshot)return false;
 ac8session::State next;
 if(!ac8session::state_from(f,next))return false;
 if(have_snapshot&&(next.epoch<authority.epoch||next.revision<authority.revision||next.changes<authority.changes))return false;
 authority=next;have_snapshot=true;return true;
}
static void write_snapshot(){
 wchar_t path[32768]{},tmp[32768]{};if(!output_dir[0]||swprintf_s(path,L"%ls\\shared-session-status.tsv",output_dir)<0||swprintf_s(tmp,L"%ls\\shared-session-status.tmp",output_dir)<0)return;
 FILE*f=_wfsopen(tmp,L"w",_SH_DENYWR);if(!f)return;
 const bool ready=connected&&session.ready();
 fprintf(f,"config_token\t%llu\n",config_token);
 fprintf(f,"format\tac8-session-status-v2\nconnected\t%d\nhave_snapshot\t%d\nrole\t%s\nself\t%llu\npeer\t%llu\nrequest_ack\t%llu\nreject\t%u\ntransport\t%s\nreason\t%s\nphase\t%u\nepoch\t%u\nrevision\t%u\nmission\t%u\ndifficulty\t%u\nwingman\t%u\nready_mask\t%u\nloaded_mask\t%u\nvote_mask\t%u\nscene\t%u\ngeneration\t%u\nchanges\t%u\ngame_adapter_ready\t0\n",
  ready?1:0,(role==Role::host||have_snapshot)?1:0,role==Role::host?"host":"guest",local_id,peer_id,request_seen,reject_code,state,reason,static_cast<uint32_t>(authority.stage),authority.epoch,authority.revision,authority.mission,authority.difficulty,authority.wingman,authority.ready,authority.loaded,authority.votes,authority.scene,authority.generation,authority.changes);
 fclose(f);MoveFileExW(tmp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
static bool decimal(const std::string&s,uint64_t&v,uint64_t limit){if(s.empty()||s.size()>20)return false;v=0;for(char c:s){if(c<'0'||c>'9'||v>(limit-static_cast<unsigned>(c-'0'))/10)return false;v=v*10+static_cast<unsigned>(c-'0');}return true;}
static void read_request(){
 wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\shared-session-command.tsv",output_dir)<0)return;
 FILE*f=_wfsopen(path,L"rb",_SH_DENYNO);if(!f)return;char buffer[4097]{};size_t n=fread(buffer,1,sizeof(buffer),f);fclose(f);if(!n||n>4096)return;
 // Fixed ordered schema, all values numeric. An unacknowledged file is never overwritten by Lua.
 const char*names[]={"request","epoch","revision","op","arg0","arg1"};uint64_t values[6]{};size_t pos=0;std::string input(buffer,n);
 if(input.find('\0')!=std::string::npos)return;
 for(size_t i=0;i<6;++i){auto end=input.find('\n',pos);if(end==std::string::npos)return;auto line=input.substr(pos,end-pos);pos=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos||line.substr(0,tab)!=names[i]||!decimal(line.substr(tab+1),values[i],i?UINT32_MAX:0x7fffffffffffffffull))return;}
 if(pos!=input.size()||!values[0]||values[0]<=request_seen)return;
 auto op=static_cast<ac8session::Op>(values[3]);ac8session::Args args{};args[0]=static_cast<uint32_t>(values[4]);args[1]=static_cast<uint32_t>(values[5]);
 // Milestone one exposes only room choice and readiness. No synthetic cutscene or flight.
 if(op!=ac8session::Op::ready&&op!=ac8session::Op::select_mission){request_seen=values[0];reject_code=static_cast<uint32_t>(ac8session::Reject::stage);return;}
 if(role==Role::host){
  if(op==ac8session::Op::ready&&(!connected||!session.ready()))return;
  reject_code=static_cast<uint32_t>(authority.apply(0,op,args,static_cast<uint32_t>(values[1]),static_cast<uint32_t>(values[2])));
  request_seen=values[0];log(reject_code?"host_intent_rejected":"host_intent_applied",reject_code);
 }else{
  if(!connected||!session.ready()||!have_snapshot)return;
  if(op==ac8session::Op::select_mission){request_seen=values[0];reject_code=static_cast<uint32_t>(ac8session::Reject::role);return;}
  ac8session::Frame frame;frame.kind=ac8session::Kind::intent;frame.epoch=static_cast<uint32_t>(values[1]);frame.revision=static_cast<uint32_t>(values[2]);frame.op=op;frame.args=args;
  if(send_session(frame)){request_seen=values[0];reject_code=0;}
 }
}
static DWORD WINAPI session_worker(void*){
 boundary(1);uint64_t published=0,status_at=0;
 while(!worker_stop.load()&&!faulted){
  boundary(0);const bool ready=connected&&session.ready();
  if(was_ready&&!ready){authority.disconnect();have_snapshot=false;}
  was_ready=ready;read_request();auto now=GetTickCount64();
  if(ready&&role==Role::host&&(published!=authority.changes||now-snapshot_sent_at>=500)){
   if(send_session(ac8session::snapshot(authority))){published=authority.changes;snapshot_sent_at=now;}
  }
  if(now-status_at>=100){write_snapshot();status_at=now;}Sleep(20);
 }
 boundary(2);write_snapshot();return 0;
}
static bool configure_worker(){
 wchar_t marker[32]{},output[32768]{},path[32768]{},steam_path[32768]{};
 if(!read_env(L"AC8_SHARED_SESSION",marker,32)||wcscmp(marker,L"25201480")||!read_env(L"AC8_COOP_RECON_OUTPUT",output,32768)||!read_env(L"AC8_SHARED_STEAM_DLL",steam_path,32768))return false;
 if(swprintf_s(path,L"%ls\\shared-session-config.tsv",output)<0)return false;
 FILE*f=_wfsopen(path,L"rb",_SH_DENYNO);if(!f)return false;char text[128]{};size_t size=fread(text,1,sizeof(text),f);fclose(f);if(size>=sizeof(text))return false;
 std::string config(text,size);auto split=config.find('\n');if(split==std::string::npos)return false;auto selected=config.substr(0,split);auto second=config.find('\n',split+1);if(second==std::string::npos)return false;auto peer=config.substr(split+1,second-split-1);auto token=config.substr(second+1);if(!token.empty()&&token.back()=='\n')token.pop_back();
 if(!decimal(token,config_token,0x1fffffffffffffull)||!config_token)return false;
 if((selected!="host"&&selected!="guest")||peer.size()!=17)return false;std::wstring wide(peer.begin(),peer.end());uint64_t id=0;if(!id_from_text(wide.c_str(),id))return false;
 SetEnvironmentVariableW(L"AC8_CONNECTION_TEST",L"25201480");SetEnvironmentVariableW(L"AC8_CONNECTION_OUTPUT",output);SetEnvironmentVariableW(L"AC8_CONNECTION_STEAM_DLL",steam_path);SetEnvironmentVariableW(L"AC8_CONNECTION_ROLE",selected=="host"?L"host":L"guest");SetEnvironmentVariableW(L"AC8_CONNECTION_PEER",wide.c_str());
 initialized=false;faulted=false;authority={};have_snapshot=was_ready=false;request_seen=0;reject_code=0;session_v2_rx=session_v2_tx=0;snapshot_sent_at=0;worker_stop=false;
 if(swprintf_s(path,L"%ls\\shared-session-command.tsv",output)<0)return false;DeleteFileW(path);
 worker=CreateThread(nullptr,0,session_worker,nullptr,0,nullptr);return worker!=nullptr;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_shared_start(void*){
 if(worker&&WaitForSingleObject(worker,0)==WAIT_OBJECT_0){CloseHandle(worker);worker=nullptr;}
 if(!worker&&!faulted)configure_worker();return 0;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_shared_stop(void*){worker_stop=true;return 0;}
