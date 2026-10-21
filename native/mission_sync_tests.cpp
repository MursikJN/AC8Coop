#define AC8_MISSION_SYNC_R26
#include "shared_session_protocol.h"
#include <cstdio>
#include <cstdlib>
using namespace ac8session;
static unsigned checks=0;
static void check(bool ok){++checks;if(!ok){fprintf(stderr,"Sync check %u failed\n",checks);exit(1);}}
static Reject action(State&s,unsigned p,Op op,uint32_t a=0,uint32_t b=0){Args args{};args[0]=a;args[1]=b;return s.apply(p,op,args,s.epoch,s.revision);}
static void commit(State&s,unsigned p,uint64_t time){check(action(s,p,Op::commit,uint32_t(time),uint32_t(time>>32))==Reject::none);}
static State room(){State s;check(action(s,0,Op::select_mission,6,1)==Reject::none);check(action(s,1,Op::loadout,23)==Reject::none);check(action(s,0,Op::ready,1)==Reject::none);check(action(s,1,Op::ready,1)==Reject::none);return s;}
static void release(State&s,uint64_t time){check(s.tick(time));const auto deadline=s.release_at;check(deadline==time+1500);commit(s,0,deadline);commit(s,1,deadline);check(!s.tick(deadline-1));check(s.tick(deadline));check(s.release_at==0&&s.committed==0&&s.loaded==0);}
static State scene(){auto s=room();check(action(s,0,Op::begin_intro,101)==Reject::none);check(action(s,0,Op::loaded)==Reject::none);check(action(s,1,Op::loaded)==Reject::none);release(s,1000);check(s.stage==Stage::cutscene);return s;}
int main(){
 auto s=room();check(action(s,1,Op::begin_intro,101)==Reject::role);check(action(s,0,Op::open_local_hangar)==Reject::stage);check(action(s,0,Op::begin_intro,101)==Reject::none);check(s.ready==0);
 check(action(s,0,Op::loaded)==Reject::none);auto before=s.changes;check(action(s,0,Op::loaded)==Reject::none&&s.changes==before);
 check(!s.tick(500000)&&s.stage==Stage::intro_loading&&s.loaded==1);check(action(s,1,Op::loaded)==Reject::none);check(s.tick(500000));
 auto first=s.release_at;commit(s,0,first);check(s.committed==1);check(s.tick(first));check(s.stage==Stage::intro_loading&&s.release_at>first&&s.committed==0);
 check(action(s,1,Op::commit,uint32_t(first),uint32_t(first>>32))==Reject::stale);const auto second=s.release_at;commit(s,0,second);commit(s,1,second);before=s.changes;commit(s,1,second);check(s.changes==before);check(s.tick(second)&&s.stage==Stage::cutscene);
 check(action(s,0,Op::vote_skip,101)==Reject::none);check(s.votes==1&&s.scene_exit==0&&s.stage==Stage::cutscene);before=s.changes;
 check(action(s,0,Op::vote_skip,101)==Reject::none&&s.changes==before);check(action(s,1,Op::vote_skip,100)==Reject::stale);
 check(action(s,1,Op::vote_skip,101)==Reject::none);check(s.votes==3&&s.scene_exit==1&&s.stage==Stage::cutscene);
 const auto old_epoch=s.epoch;check(action(s,1,Op::scene_segment,102)==Reject::role);check(action(s,0,Op::scene_segment,102)==Reject::none);check(s.votes==0&&s.scene_exit==0&&s.epoch>old_epoch);before=s.changes;
 check(action(s,0,Op::scene_segment,102)==Reject::none&&s.changes==before);Args vote{};vote[0]=101;check(s.apply(1,Op::vote_skip,vote,old_epoch,s.revision)==Reject::stale);
 check(action(s,1,Op::scene_ended,102)==Reject::role);check(action(s,0,Op::scene_ended,102)==Reject::none);check(s.stage==Stage::hangar_loading&&s.scene_exit==2);
 auto hangar_scene=s;check(action(hangar_scene,0,Op::begin_flight_scene,103)==Reject::none);check(hangar_scene.stage==Stage::cutscene&&hangar_scene.scene_return==3);check(action(hangar_scene,0,Op::scene_ended,103)==Reject::none&&hangar_scene.stage==Stage::hangar_loading);
 check(action(s,1,Op::loaded)==Reject::none);check(!s.tick(600000));check(action(s,0,Op::loaded)==Reject::not_ready);check(action(s,0,Op::local_hangar_arrived,7,23)==Reject::none);check(s.loaded==3&&s.stage==Stage::hangar_loading);release(s,600000);check(s.stage==Stage::hangar&&s.ready==0);
 check(action(s,0,Op::start_sortie)==Reject::not_ready);check(action(s,0,Op::ready,1)==Reject::none);check(action(s,1,Op::ready,1)==Reject::none);check(action(s,1,Op::start_sortie)==Reject::role);
 check(action(s,0,Op::start_sortie)==Reject::none);check(s.generation==1&&s.ready==0);check(action(s,0,Op::local_flight_arrived)==Reject::none);check(s.loaded==1&&s.stage==Stage::flight_loading);check(!s.tick(700000));check(action(s,1,Op::loaded)==Reject::none);release(s,700000);check(s.stage==Stage::flight&&s.generation==1);
 check(action(s,1,Op::begin_flight_scene,103)==Reject::role);check(action(s,0,Op::begin_flight_scene,103)==Reject::none);check(s.stage==Stage::cutscene&&s.scene_return==6&&s.votes==0);check(action(s,0,Op::vote_skip,103)==Reject::none);check(action(s,1,Op::vote_skip,103)==Reject::none);check(s.stage==Stage::cutscene);check(action(s,0,Op::scene_ended,103)==Reject::none);check(s.stage==Stage::flight&&s.generation==1);check(action(s,0,Op::begin_flight_scene,103)==Reject::stale);
 s=scene();check(action(s,0,Op::vote_skip,101)==Reject::none);s.disconnect();check(s.stage==Stage::stopped&&!s.votes&&!s.release_at);check(action(s,1,Op::loaded)==Reject::stage);
 s=room();check(action(s,0,Op::begin_intro,1)==Reject::none);check(action(s,0,Op::loaded)==Reject::none);check(action(s,1,Op::loaded)==Reject::none);check(s.tick(1000));commit(s,0,s.release_at);
 auto f=snapshot(s);f.sender=1;f.session=f.echo=9;f.sequence=1;auto bytes=encode(f);Frame parsed;State mirror;check(decode(bytes.data(),bytes.size(),parsed)&&state_from(parsed,mirror));check(mirror.committed==1&&mirror.release_at==s.release_at);
 bytes[4]=2;check(!decode(bytes.data(),bytes.size(),parsed));f.args[11]=4;check(!state_from(f,mirror));f=snapshot(s);f.args[0]=unsigned(Stage::flight);check(!state_from(f,mirror));
 check(action(s,1,Op::abort_session)==Reject::role);check(action(s,0,Op::abort_session)==Reject::none&&s.stage==Stage::stopped&&!s.release_at);
 printf("%u mission synchronization checks passed\n",checks);
}
