#define AC8_LOBBY_TRANSPORT
#include "connection_test.cpp"
#include <string>
#include <limits>
static ac8lobby::Frame lobby_local;
static uint64_t lobby_sent_at=0;
static bool lobby_enabled=false;
static bool lobby_guard(){
 wchar_t marker[32]{},expected[32768]{},actual[32768]{};HMODULE self=nullptr;
 if(!read_env(L"AC8_COOP_LOBBY",marker,32)||wcscmp(marker,L"25201480")||!read_env(L"AC8_COOP_LOBBY_DLL",expected,32768))return false;
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&lobby_guard),&self))return false;
 const auto n=GetModuleFileNameW(self,actual,32768);return n>0&&n<32768&&!_wcsicmp(actual,expected);
}
static bool lobby_read_command(){
 wchar_t dir[32768]{},path[32768]{};if(!read_env(L"AC8_CONNECTION_OUTPUT",dir,32768)||swprintf_s(path,L"%ls\\lobby-command.tsv",dir)<0)return false;
 FILE*f=_wfsopen(path,L"rb",_SH_DENYNO);if(!f)return false;char b[513]{};const auto count=fread(b,1,513,f);fclose(f);if(!count||count>512)return false;
 std::string text(b,count);if(text.find('\0')!=std::string::npos)return false;
 ac8lobby::Frame next;unsigned seen=0;size_t pos=0;
 while(pos<text.size()){
  auto end=text.find('\n',pos);if(end==std::string::npos)return false;std::string line=text.substr(pos,end-pos);pos=end+1;
  if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos)return false;
  auto key=line.substr(0,tab),value=line.substr(tab+1);unsigned bit=0;uint32_t*target=nullptr;
  if(key=="format"){if(value!="ac8-lobby-command-v1")return false;bit=1;}
  else {
   if(key=="revision"){bit=2;target=&next.revision;}else if(key=="ready_revision"){bit=4;target=&next.ready_revision;}
   else if(key=="launch"){bit=8;target=&next.launch;}else if(key=="mission"){bit=16;target=&next.mission;}
   else if(key=="plane"){bit=32;target=&next.plane;}else if(key=="flags"){bit=64;target=&next.flags;}
   else if(key=="phase"){bit=128;}else return false;
   if(value.empty()||value.size()>10)return false;uint64_t n=0;
   for(char ch:value){if(ch<'0'||ch>'9')return false;n=n*10+static_cast<unsigned>(ch-'0');if(n>UINT32_MAX)return false;}
   if(target)*target=static_cast<uint32_t>(n);else next.phase=static_cast<ac8lobby::Phase>(n);
  }
  if(seen&bit)return false;seen|=bit;
 }
 next.sender=next.session=next.echo=next.sequence=1;
 if(seen!=255||!ac8lobby::valid(next))return false;lobby_local=next;return true;
}
static void lobby_snapshot(){
 if(!output_dir[0])return;wchar_t path[32768]{},tmp[32768]{};
 if(swprintf_s(path,L"%ls\\lobby-status.tsv",output_dir)<0||swprintf_s(tmp,L"%ls\\lobby-status.tmp",output_dir)<0)return;
 FILE*f=_wfsopen(tmp,L"w",_SH_DENYWR);if(!f)return;auto now=GetTickCount64();const auto&p=lobby_mailbox;
 const bool ready=initialized&&!faulted&&connected&&session.ready();
 fprintf(f,"format\tac8-lobby-status-v1\nconnected\t%d\nself\t%llu\npeer\t%llu\nsession\t%llu\npeer_session\t%llu\nsequence\t%llu\npeer_age_ms\t%llu\nrevision\t%u\nready_revision\t%u\nlaunch\t%u\nmission\t%u\nplane\t%u\nflags\t%u\nphase\t%u\ntransport\t%s\nreason\t%s\n",
 ready?1:0,local_id,peer_id,session.nonce,session.remote,lobby_rx,lobby_rx&&now>=lobby_received_at?now-lobby_received_at:UINT64_MAX,
 p.revision,p.ready_revision,p.launch,p.mission,p.plane,p.flags,static_cast<uint32_t>(p.phase),state,reason);
 fclose(f);MoveFileExW(tmp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
static void lobby_dispatch(unsigned action){
 if(!lobby_guard())return;
 if(action==3){
  if(faulted|| (initialized&&action_thread!=GetCurrentThreadId()))return;
  if(lobby_enabled)boundary(2);
  lobby_enabled=false;initialized=false;lobby_sent_at=0;lobby_local={};lobby_snapshot();return;
 }
 if(action==0){
  if(lobby_enabled)return;
  if(!lobby_read_command())return;
  boundary(1);lobby_enabled=initialized&&!faulted;lobby_snapshot();return;
 }
 if(!lobby_enabled||action_thread!=GetCurrentThreadId())return;
 if(action==2){boundary(2);lobby_enabled=false;lobby_snapshot();return;}
 boundary(0);
 const auto now=GetTickCount64();
 if(connected&&session.ready()&&now-lobby_sent_at>=100){
  lobby_sent_at=now;
  if(!lobby_read_command()){connection_ended("invalid_local_lobby_command");lobby_snapshot();return;}
  if(lobby_tx==UINT64_MAX){connection_ended("lobby_sequence_exhausted");lobby_snapshot();return;}
  auto frame=lobby_local;frame.sender=local_id;frame.session=session.nonce;frame.echo=session.remote;frame.sequence=++lobby_tx;
  const auto bytes=ac8lobby::encode(frame);
  if(api.send(api.sockets,connection,bytes.data(),static_cast<uint32>(bytes.size()),k_nSteamNetworkingSend_ReliableNoNagle,nullptr)!=k_EResultOK)connection_ended("lobby_send_failed");
 }
 lobby_snapshot();
}
static int lobby_boundary(unsigned action){__try{lobby_dispatch(action);}__except(EXCEPTION_EXECUTE_HANDLER){faulted=true;status("ERROR_LOBBY_NATIVE_EXCEPTION");}return 0;}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_lobby_start(void*){return lobby_boundary(0);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_lobby_pump(void*){return lobby_boundary(1);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_lobby_stop(void*){return lobby_boundary(2);}

extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_lobby_reset(void*){return lobby_boundary(3);}
