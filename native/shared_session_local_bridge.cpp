#include "shared_session_loopback.h"
#include <atomic>
#include <cstdio>
#include <share.h>
#include <string>
using namespace ac8session;
static HANDLE worker=nullptr;static std::atomic<bool> stop_requested{false};
static wchar_t output[32768]{};static bool host=false;static uint16_t port=0;static uint64_t token=0;
static State model;static uint64_t acknowledged=0;static unsigned reject=0;static bool snapshot_received=false;
static uint64_t guest_ack=0,pending_sequence=0,pending_request=0,confirmed=0;static unsigned guest_reject=0;
static bool adapter_enabled=false;
#ifdef AC8_MISSION_SYNC_R26
static void trace(const char*event,unsigned player,Op op,unsigned code){
 wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\mission-sync-events.tsv",output)<0)return;FILE*f=_wfsopen(path,L"a",_SH_DENYWR);if(!f)return;
 fprintf(f,"%llu\t%s\tplayer=%u\top=%u\treject=%u\tphase=%u\tepoch=%u\tscene=%u\tready=%u\tloaded=%u\tcommitted=%u\tvotes=%u\trelease_at=%llu\tchanges=%u\n",GetTickCount64(),event,player,unsigned(op),code,unsigned(model.stage),model.epoch,model.scene,model.ready,model.loaded,model.committed,model.votes,model.release_at,model.changes);fclose(f);
}
#endif
static bool decimal(const std::string&s,uint64_t&v,uint64_t limit){
 v=0;if(s.empty()||s.size()>20)return false;for(char c:s){if(c<'0'||c>'9')return false;unsigned digit=c-'0';if(digit>limit||v>(limit-digit)/10)return false;v=v*10+digit;}return true;
}
static void log_event(const char*event,unsigned code=0){
 wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\local-transport.log",output)<0)return;
 FILE*f=_wfsopen(path,L"a",_SH_DENYWR);if(f){fprintf(f,"%llu\t%s\t%u\n",GetTickCount64(),event,code);fclose(f);}
}
static void status(const Loopback&link,const char*phase){
 wchar_t path[32768]{},temp[32768]{};
 if(swprintf_s(path,L"%ls\\shared-session-status.tsv",output)<0||swprintf_s(temp,L"%ls\\shared-session-status.tmp",output)<0)return;
 FILE*f=_wfsopen(temp,L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"format\tac8-session-status-v2\nconfig_token\t%llu\ntransport\t%s\nreason\t%s\nrole\t%s\nconnected\t%d\nhave_snapshot\t%d\nrequest_ack\t%llu\nreject\t%u\nphase\t%u\nepoch\t%u\nrevision\t%u\nmission\t%u\ndifficulty\t%u\nready_mask\t%u\nchanges\t%u\ngame_adapter_ready\t0\nport\t%u\n",
 token,phase,link.error,host?"host":"guest",link.connected?1:0,(host||snapshot_received)?1:0,acknowledged,reject,static_cast<unsigned>(model.stage),model.epoch,model.revision,model.mission,model.difficulty,model.ready,model.changes,link.port);
 fprintf(f,"host_aircraft\t%u\nguest_aircraft\t%u\nguest_weapon1\t%u\nguest_weapon2\t%u\nguest_reject\t%u\nguest_ack\t%llu\nrequest_confirmed\t%llu\n",model.planes[0].aircraft,model.planes[1].aircraft,model.planes[1].weapon1,model.planes[1].weapon2,guest_reject,guest_ack,host?acknowledged:confirmed);
 fprintf(f,"local_hangar_adapter\t%d\n",adapter_enabled?1:0);
#ifdef AC8_MISSION_SYNC_R26
 fprintf(f,"mission_sync\t1\nloaded_mask\t%u\nvote_mask\t%u\nscene\t%u\nscene_exit\t%u\ngeneration\t%u\ncommit_mask\t%u\nrelease_at\t%llu\nlocal_tick\t%llu\nscene_return\t%u\n",model.loaded,model.votes,model.scene,model.scene_exit,model.generation,model.committed,model.release_at,GetTickCount64(),model.scene_return);
 fprintf(f,"hangar_scene_supported\t1\n");
#endif
 fclose(f);MoveFileExW(temp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
static bool request(Loopback&link){
 wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\shared-session-command.tsv",output)<0)return false;
 FILE*f=_wfsopen(path,L"rb",_SH_DENYNO);if(!f)return false;
 char buffer[4097]{};size_t size=fread(buffer,1,sizeof(buffer),f);fclose(f);if(!size||size>4096)return false;
 std::string input(buffer,size);if(input.find('\0')!=std::string::npos)return false;
 const char*keys[]={"request","epoch","revision","op","arg0","arg1"};uint64_t values[6]{};size_t position=0;
 for(size_t i=0;i<6;++i){size_t end=input.find('\n',position);if(end==std::string::npos)return false;std::string line=input.substr(position,end-position);position=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();size_t tab=line.find('\t');if(tab==std::string::npos||line.substr(0,tab)!=keys[i]||!decimal(line.substr(tab+1),values[i],i?UINT32_MAX:0x1fffffffffffffull))return false;}
 if(position!=input.size()||!values[0]||values[0]<=acknowledged)return false;
 Op op=static_cast<Op>(values[3]);Args args{};args[0]=static_cast<uint32_t>(values[4]);args[1]=static_cast<uint32_t>(values[5]);
 if(op==Op::loadout){args[1]=0;args[2]=0;}
 const bool adapter_op=op==Op::open_local_hangar||op==Op::local_hangar_arrived||op==Op::start_sortie||op==Op::local_flight_arrived;
 bool allowed=op==Op::ready||op==Op::select_mission||op==Op::loadout||(host&&adapter_enabled&&adapter_op);
#ifdef AC8_MISSION_SYNC_R26
 allowed=allowed||op==Op::loaded||op==Op::vote_skip||op==Op::commit||(host&&(op==Op::begin_intro||op==Op::scene_ended||op==Op::scene_segment||op==Op::abort_session||op==Op::begin_flight_scene));
#endif
 if(!allowed){acknowledged=values[0];reject=static_cast<unsigned>(Reject::stage);
#ifdef AC8_MISSION_SYNC_R26
  if(!host)confirmed=acknowledged;
#endif
  return true;}
 if(host){
  if(op==Op::ready&&!link.connected)return false;
  reject=static_cast<unsigned>(model.apply(0,op,args,static_cast<uint32_t>(values[1]),static_cast<uint32_t>(values[2])));acknowledged=values[0];log_event("host_request",reject);
#ifdef AC8_MISSION_SYNC_R26
  trace("host_request",0,op,reject);
#endif
  return true;
 }
 if(!link.connected||!snapshot_received||pending_sequence)return false;
 if(op==Op::select_mission){reject=static_cast<unsigned>(Reject::role);acknowledged=values[0];
#ifdef AC8_MISSION_SYNC_R26
  confirmed=acknowledged;
#endif
  return true;}
 Frame frame;frame.kind=Kind::intent;frame.op=op;frame.args=args;frame.epoch=static_cast<uint32_t>(values[1]);frame.revision=static_cast<uint32_t>(values[2]);
 if(!link.send_frame(frame))return false;pending_sequence=link.last_sequence();pending_request=values[0];acknowledged=values[0];reject=0;log_event("guest_request_sent");return true;
}
static DWORD WINAPI run(void*){
 Loopback link;log_event("worker_start");if(!link.open(host,port,token)){status(link,"error");log_event("open_failed");return 0;}
 uint64_t publish_at=0,status_at=0,published=0,published_ack=0;bool ok=true;
 while(!stop_requested){
  ok=link.poll([](const Frame&f){
   if(host){
    bool allowed=f.op==Op::ready||f.op==Op::loadout;
#ifdef AC8_MISSION_SYNC_R26
    allowed=allowed||f.op==Op::loaded||f.op==Op::vote_skip||f.op==Op::commit;
#endif
    if(f.kind!=Kind::intent||!allowed)return false;
    guest_reject=static_cast<unsigned>(model.apply(1,f.op,f.args,f.epoch,f.revision));guest_ack=f.sequence;
#ifdef AC8_MISSION_SYNC_R26
    trace("guest_request",1,f.op,guest_reject);
#else
    reject=guest_reject;
#endif
    log_event("guest_request_received",guest_reject);return true;
   }
   State next;if(f.kind!=Kind::snapshot||!state_from(f,next))return false;
   if(snapshot_received&&(next.epoch<model.epoch||next.revision<model.revision||next.changes<model.changes))return false;
   model=next;snapshot_received=true;
   guest_ack=static_cast<uint64_t>(f.args[36])|(static_cast<uint64_t>(f.args[37])<<32);guest_reject=f.args[38];
   if(pending_sequence&&guest_ack>=pending_sequence){confirmed=pending_request;reject=guest_reject;pending_sequence=0;}
   return true;
  });
  if(!ok){
   model.disconnect();status(link,"disconnected");log_event("transport_closed");
   if(host&&model.stage==Stage::lobby){model.planes[1]={};link.reset_peer();published=0;guest_ack=guest_reject=0;continue;}
   return 0;
  }
  request(link);uint64_t now=GetTickCount64();
#ifdef AC8_MISSION_SYNC_R26
  if(host&&link.connected&&model.tick(now))trace("barrier_tick",0,Op::loaded,0);
#endif
  if(host&&link.connected&&(published!=model.changes||published_ack!=guest_ack||now-publish_at>=300)){
   Frame frame=snapshot(model);frame.args[36]=static_cast<uint32_t>(guest_ack);frame.args[37]=static_cast<uint32_t>(guest_ack>>32);frame.args[38]=guest_reject;
   if(link.send_frame(frame)){published=model.changes;published_ack=guest_ack;publish_at=now;}
  }
  if(now-status_at>=100){status(link,link.connected?"connected":"waiting");status_at=now;}
  Sleep(10);
 }
 link.close();model.disconnect();status(link,"stopped");log_event("worker_stop");return 0;
}
static bool configure(){
 wchar_t marker[32]{},role_text[16]{},port_text[16]{},token_text[32]{};
 if(!GetEnvironmentVariableW(L"AC8_LOCAL_SESSION",marker,32)||wcscmp(marker,L"25201480"))return false;
#ifdef AC8_MISSION_SYNC_R26
 if(!GetEnvironmentVariableW(L"AC8_MISSION_SYNC",marker,32)||wcscmp(marker,L"25201480"))return false;
#endif
 if(!GetEnvironmentVariableW(L"AC8_COOP_RECON_OUTPUT",output,32768)||!GetEnvironmentVariableW(L"AC8_LOCAL_ROLE",role_text,16)||!GetEnvironmentVariableW(L"AC8_LOCAL_PORT",port_text,16)||!GetEnvironmentVariableW(L"AC8_LOCAL_TOKEN",token_text,32))return false;
 if(wcscmp(role_text,L"host")&&wcscmp(role_text,L"guest"))return false;host=!wcscmp(role_text,L"host");
 wchar_t adapter_marker[32]{};adapter_enabled=GetEnvironmentVariableW(L"AC8_LOCAL_HANGAR",adapter_marker,32)&&!wcscmp(adapter_marker,L"25201480");
 auto narrow=[](const wchar_t*s){std::string value;for(;*s;++s){if(*s>127)return std::string{};value+=static_cast<char>(*s);}return value;};
 uint64_t p=0;if(!decimal(narrow(port_text),p,65535)||!decimal(narrow(token_text),token,0x1fffffffffffffull)||!token||(!host&&!p))return false;port=static_cast<uint16_t>(p);
 model={};acknowledged=reject=0;guest_ack=guest_reject=0;pending_sequence=pending_request=confirmed=0;snapshot_received=false;stop_requested=false;
 wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\shared-session-command.tsv",output)<0)return false;DeleteFileW(path);
 worker=CreateThread(nullptr,0,run,nullptr,0,nullptr);return worker!=nullptr;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_local_start(void*){
 HMODULE pinned=nullptr;
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&run),&pinned))return 0;
 if(worker&&WaitForSingleObject(worker,0)==WAIT_OBJECT_0){CloseHandle(worker);worker=nullptr;}
 if(!worker)configure();return 0;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_local_stop(void*){stop_requested=true;return 0;}
// For the external simulator/test process: wait for CRT/file cleanup before process exit.
extern "C" __declspec(dllexport) int __cdecl ac8_local_wait_stopped(unsigned long milliseconds){
 if(milliseconds>5000)milliseconds=5000;
 return !worker||WaitForSingleObject(worker,milliseconds)==WAIT_OBJECT_0?1:0;
}
#ifdef AC8_MISSION_SYNC_R26
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_sync26_clock(void*){
 wchar_t path[32768]{};if(!output[0]||swprintf_s(path,L"%ls\\sync-clock.tsv",output)<0)return 0;FILE*f=_wfsopen(path,L"w",_SH_DENYWR);if(f){fprintf(f,"tick\t%llu\n",GetTickCount64());fclose(f);}return 0;
}
#endif
