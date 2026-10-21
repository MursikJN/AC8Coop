#include "shared_session_loopback.h"
#include <cstdio>
#include <cstdlib>
#include <string>
using namespace ac8session;
// Two real OS processes exercise the same authority/wire model used by the Steam bridge.
// No game adapter, aircraft, map, Steam account or game save is involved.
static bool number(const char*s,uint64_t&value,uint64_t limit){
 value=0;if(!s||!*s)return false;
 for(;*s;++s){if(*s<'0'||*s>'9')return false;unsigned digit=*s-'0';if(digit>limit||value>(limit-digit)/10)return false;value=value*10+digit;}return true;
}
int main(int argc,char**argv){
 if(argc!=5){fprintf(stderr,"usage: local_trial host|guest port token output-prefix\n");return 2;}
 bool host=std::string(argv[1])=="host";uint64_t port=0,token=0;
 if((!host&&std::string(argv[1])!="guest")||!number(argv[2],port,65535)||!number(argv[3],token,UINT64_MAX)||!token)return 2;
 const std::string prefix=argv[4];FILE*log=nullptr;fopen_s(&log,(prefix+".log").c_str(),"w");if(!log)return 2;
 Loopback link;if(!link.open(host,static_cast<uint16_t>(port),token)){fprintf(log,"open_error=%s\n",link.error);fclose(log);return 3;}
 if(host){FILE*f=nullptr;fopen_s(&f,(prefix+".port").c_str(),"w");if(!f){fclose(log);return 3;}fprintf(f,"%u",link.port);fclose(f);}
 State state;unsigned rejected=0;bool forged=false,unready=false,complete=false,saw_reset=false;
 uint32_t readied_revision=0;uint64_t start=GetTickCount64(),last_sent=0;
 if(host){Args a{};a[0]=1;a[1]=2;if(state.apply(0,Op::select_mission,a,state.epoch,state.revision)!=Reject::none)return 4;}
 while(GetTickCount64()-start<10000){
  bool ok=link.poll([&](const Frame&f){
   if(host){
    if(f.kind!=Kind::intent)return false;
    auto result=state.apply(1,f.op,f.args,f.epoch,f.revision);
    if(result==Reject::role&&f.op==Op::select_mission){++rejected;fprintf(log,"guest_mission_change_rejected=1\n");}
    else if(result!=Reject::none)return false;
    return true;
   }
   if(f.kind!=Kind::snapshot)return false;State next;if(!state_from(f,next))return false;
   if(next.epoch<state.epoch||next.revision<state.revision||next.changes<state.changes)return false;
   state=next;
   fprintf(log,"snapshot mission=%u difficulty=%u ready=%u revision=%u\n",state.mission,state.difficulty,state.ready,state.revision);
   if(state.mission==6&&state.ready==0)saw_reset=true;
   if(unready&&state.mission==6&&state.ready==1)complete=true;
   return true;
  });
  if(!ok&&!complete){fprintf(log,"transport_error=%s\n",link.error);break;}
  if(complete)break;
  if(link.connected){
   if(host){
    Args a{};
    if(state.ready==2){a[0]=1;state.apply(0,Op::ready,a,state.epoch,state.revision);}
    if(state.mission==1&&state.ready==3){a[0]=6;a[1]=3;state.apply(0,Op::select_mission,a,state.epoch,state.revision);fprintf(log,"host_selection_changed_and_ready_reset=1\n");}
    if(state.mission==6&&state.ready==1&&rejected==1&&unready)complete=true;
    if(state.mission==6&&state.ready==3)unready=true;
    if(GetTickCount64()-last_sent>=20&&link.send_frame(snapshot(state)))last_sent=GetTickCount64();
    // Keep the final snapshot available until the guest acknowledges it by closing.
    if(complete){
     bool queued=false;
     for(unsigned i=0;i<40;++i){
      if(!queued)queued=link.send_frame(snapshot(state));
      if(!link.poll([](const Frame&){return true;}))break;
      Sleep(5);
     }
     break;
    }
   }else if(state.mission){
    Frame f;f.epoch=state.epoch;f.revision=state.revision;
    if(!forged){f.op=Op::select_mission;f.args[0]=99;f.args[1]=1;if(link.send_frame(f))forged=true;}
    else if(state.mission==6&&state.ready==3&&!unready){f.op=Op::ready;f.args[0]=0;if(link.send_frame(f))unready=true;}
    else if(!unready&&state.revision!=readied_revision){f.op=Op::ready;f.args[0]=1;if(link.send_frame(f))readied_revision=state.revision;}
   }
  }
  Sleep(2);
 }
 bool passed=complete&&(host?rejected==1:saw_reset);
 fprintf(log,"result=%s\nkind=two_process_loopback_control_trial\ngameplay_tested=0\n",passed?"passed":"failed");fclose(log);
 printf("%s: %s (loopback control only)\n",host?"host":"guest",passed?"passed":"failed");return passed?0:5;
}
