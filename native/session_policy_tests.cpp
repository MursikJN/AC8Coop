#define AC8_MISSION_SYNC_R26
#define AC8_STEAM_COOP_R27
#define AC8_CINEMA_SYNC_R28
#define AC8_SESSION_POLICY_R29
#include "shared_session_protocol.h"
#include "session_policy.h"
#include "steam_invite_core.h"
#include <cassert>
#include <cstdio>
using namespace ac8session;
static unsigned checks=0;
static void expect(bool ok){++checks;assert(ok);}
static Reject op(State&s,unsigned who,Op action,uint32_t a=0,uint32_t b=0){Args args{};args[0]=a;args[1]=b;return s.apply(who,action,args,s.epoch,s.revision);}
static void wire(const State&s){auto f=snapshot(s);f.sender=1;f.session=2;f.echo=3;f.sequence=1;auto bytes=encode(f);Frame d;State out;expect(decode(bytes.data(),bytes.size(),d)&&state_from(d,out));expect(out.restart_id==s.restart_id&&out.restart_ack==s.restart_ack&&out.stop_reason==s.stop_reason&&out.stage==s.stage);}
int main(){
 State s;s.mission=6;s.difficulty=1;expect(s.accepts_join());s.ready=3;auto rev=s.revision;
 expect(op(s,0,Op::select_mission,6,1)==Reject::none&&s.ready==3&&s.revision==rev);
 expect(op(s,0,Op::select_mission,6,2)==Reject::none&&!s.ready&&s.revision==rev+1);
 s.planes[0].aircraft=7;s.planes[1].aircraft=23;s.ready=3;
 expect(op(s,1,Op::loadout,23)==Reject::none&&s.ready==3);
 expect(op(s,1,Op::loadout,23,16)==Reject::none&&s.ready==1);rev=s.revision;
 Args old{};old[0]=1;expect(s.apply(1,Op::ready,old,s.epoch,rev-1)==Reject::stale);
 s.stage=Stage::hangar;s.ready=3;expect(op(s,1,Op::invalidate_ready)==Reject::role);expect(op(s,0,Op::invalidate_ready)==Reject::none&&!s.ready);
 s.stage=Stage::flight_loading;s.generation=3;auto old_epoch=s.epoch++;Args cancel{};cancel[0]=3;
 expect(s.apply(1,Op::cancel,cancel,old_epoch,s.revision)==Reject::none&&s.stage==Stage::stopped&&s.stop_reason==StopReason::cancelled);expect(!s.accepts_join());wire(s);
 expect(s.apply(1,Op::cancel,cancel,old_epoch,s.revision)==Reject::stale);expect(!s.ready&&!s.loaded&&!s.votes&&!s.committed&&!s.release_at&&!s.cinema_at);
 State t;t.stage=Stage::flight_loading;t.mission=6;Watchdog w;expect(!w.tick(t,100));
 for(uint64_t time=1100;time<120100;time+=1000){t.release_at=time+1500;t.committed=uint32_t(time%3);expect(!w.tick(t,time));}
 expect(w.tick(t,120100)&&t.stage==Stage::stopped&&t.stop_reason==StopReason::load_timeout);
 t={};t.stage=Stage::hangar_loading;w={};expect(!w.tick(t,0));expect(!w.tick(t,99999999)); // Manual aircraft selection has no arbitrary limit.
 t={};t.stage=Stage::cutscene;t.cinema_prepared=3;t.cinema_state=2;t.cinema_finished=1;w={};expect(!w.tick(t,100));expect(w.tick(t,120100));
 t={};t.stage=Stage::flight;t.mission=6;t.generation=10;t.planes[0].aircraft=7;t.planes[1].aircraft=23;
 expect(op(t,1,Op::restart,10)==Reject::role);expect(op(t,0,Op::restart,9)==Reject::stale);expect(op(t,0,Op::restart,10)==Reject::none);
 expect(t.stage==Stage::restart_loading&&t.generation==11&&t.restart_id==1&&!t.accepts_join());wire(t);
 expect(op(t,0,Op::restart,11)==Reject::stage);for(unsigned p=0;p<2;++p)expect(op(t,p,Op::loaded)==Reject::none);
 expect(t.tick(1000));for(unsigned p=0;p<2;++p)expect(op(t,p,Op::commit,2500)==Reject::none);
 expect(t.tick(2500)&&t.stage==Stage::restart_exit);expect(op(t,0,Op::restart_ack,1)==Reject::role);expect(op(t,1,Op::restart_ack,2)==Reject::stale);
 expect(op(t,1,Op::restart_ack,1)==Reject::none&&t.restart_ack==2);wire(t);
 t.disconnect();expect(t.stage==Stage::restart_exit&&t.restart_ack==2);expect(op(t,0,Op::cancel,t.generation)==Reject::stage);wire(t);
 t={};t.stage=Stage::flight;t.generation=4;t.disconnect();expect(t.stage==Stage::stopped&&t.stop_reason==StopReason::peer_lost&&t.generation==5&&!t.accepts_join());wire(t);
 t={};t.ready=3;t.disconnect();expect(t.stage==Stage::lobby&&!t.ready&&t.accepts_join());
 Frame f;f.sender=1;f.session=2;f.echo=3;f.sequence=4;f.op=Op::cancel;f.args[0]=99;auto data=encode(f);Frame decoded;expect(data.size()==320&&decode(data.data(),data.size(),decoded));data[4]=6;expect(!decode(data.data(),data.size(),decoded));
 t={};auto snap=snapshot(t);snap.args[63]=1;State out;expect(!state_from(snap,out));expect(ac8invite::encode(76561198000000001ull).find("ac8coop:v7:")==0);
 printf("Session readiness, loading watchdog, lobby-only join, cancellation and coordinated clean restart: %u checks passed\n",checks);
}
