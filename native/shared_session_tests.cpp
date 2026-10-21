#include "shared_session_protocol.h"
#include <cstdio>
#include <cstdlib>
using namespace ac8session;
static unsigned checks=0;
static void check(bool v){if(!v){fprintf(stderr,"session check failed: %u\n",checks+1);exit(1);}++checks;}
static Reject act(State&s,unsigned p,Op op,std::initializer_list<uint32_t> values={}){Args a{};size_t n=0;for(auto v:values)a[n++]=v;return s.apply(p,op,a,s.epoch,s.revision);}
static State room(){State s;check(act(s,0,Op::select_mission,{1,2})==Reject::none);return s;}
static State scene(){auto s=room();check(act(s,0,Op::ready,{1})==Reject::none);check(act(s,1,Op::ready,{1})==Reject::none);check(s.can_intro());check(act(s,0,Op::begin_intro,{101})==Reject::none);check(s.ready==0);check(act(s,0,Op::loaded)==Reject::none);check(s.stage==Stage::intro_loading);check(act(s,1,Op::loaded)==Reject::none);check(s.stage==Stage::cutscene);return s;}
static State hangar(){auto s=scene();check(act(s,0,Op::scene_ended,{101})==Reject::none);check(act(s,0,Op::loaded)==Reject::none);check(act(s,1,Op::loaded)==Reject::none);check(s.stage==Stage::hangar&&s.ready==0);return s;}
int main(){
 auto s=room();auto old=s;check(act(s,1,Op::select_mission,{2,3})==Reject::role);check(s.changes==old.changes&&s.mission==1);
 check(act(s,0,Op::begin_intro,{101})==Reject::not_ready);
 check(act(s,0,Op::ready,{1})==Reject::none);check(act(s,1,Op::ready,{1})==Reject::none);
 Args a{};a[0]=1;uint32_t stale=s.revision;check(act(s,0,Op::select_mission,{2,3})==Reject::none);check(s.ready==0);
 check(s.apply(1,Op::ready,a,s.epoch,stale)==Reject::stale);check(s.ready==0);
 s=scene();uint32_t epoch=s.epoch;check(act(s,1,Op::vote_skip,{100})==Reject::stale);check(s.votes==0);
 check(act(s,1,Op::vote_skip,{101})==Reject::none);check(s.votes==2&&s.stage==Stage::cutscene);
 check(act(s,1,Op::vote_skip,{101})==Reject::none);check(s.votes==2&&s.stage==Stage::cutscene);
 check(act(s,0,Op::vote_skip,{101})==Reject::none);check(s.stage==Stage::hangar_loading&&s.votes==0&&s.epoch>epoch);
 check(s.apply(1,Op::vote_skip,a,epoch,s.revision)==Reject::stale);
 s=scene();check(act(s,1,Op::scene_ended,{101})==Reject::role);check(s.stage==Stage::cutscene);
 s=hangar();check(act(s,1,Op::assign_wingman,{2})==Reject::role);check(act(s,0,Op::assign_wingman,{4})==Reject::value);
 check(act(s,0,Op::assign_wingman,{2})==Reject::none);check(s.wingman==2);
 check(act(s,1,Op::ready,{1})==Reject::not_ready);check(act(s,0,Op::start_sortie)==Reject::not_ready);
 check(act(s,0,Op::loadout,{23,1,2,2,41,42})==Reject::none);check(act(s,1,Op::loadout,{12,2,3,1,51})==Reject::none);
 check(s.planes[0].aircraft==23&&s.planes[1].aircraft==12);check(act(s,1,Op::loadout,{12,2,3,2,51,51})==Reject::value);
 check(act(s,0,Op::ready,{1})==Reject::none);check(act(s,1,Op::ready,{1})==Reject::none);check(s.can_sortie());
 check(act(s,1,Op::start_sortie)==Reject::role);check(s.stage==Stage::hangar);
 check(act(s,1,Op::loadout,{12,2,4})==Reject::none);check(s.ready==1&&!s.can_sortie());check(act(s,1,Op::ready,{1})==Reject::none);
 check(act(s,0,Op::start_sortie)==Reject::none);check(s.stage==Stage::flight_loading&&s.ready==0&&s.generation==1);
 check(act(s,0,Op::loaded)==Reject::none);check(s.stage==Stage::flight_loading);check(act(s,1,Op::loaded)==Reject::none);check(s.stage==Stage::flight);
 auto f=snapshot(s);f.sender=1;f.session=2;f.echo=3;f.sequence=4;auto bytes=encode(f);Frame decoded;State mirror;
 check(decode(bytes.data(),bytes.size(),decoded)&&state_from(decoded,mirror));check(mirror.generation==1&&mirror.stage==Stage::flight&&mirror.planes[1].weapon2==4);
 for(size_t n=0;n<packet_size;++n)check(!decode(bytes.data(),n,decoded));
 bytes[60]=1;check(!decode(bytes.data(),bytes.size(),decoded));bytes=encode(f);bytes[4]=1;check(!decode(bytes.data(),bytes.size(),decoded));
 f.args[47]=1;check(!state_from(f,mirror));f.args[47]=0;f.args[0]=99;check(!state_from(f,mirror));
 f={};f.sender=1;f.session=2;f.echo=3;f.sequence=1;f.args[0]=1;check(valid(f));f.args[47]=1;check(!valid(f));
 s.disconnect();check(s.stage==Stage::stopped&&s.ready==0);check(act(s,1,Op::ready,{1})==Reject::stage);
 s=room();s.changes=UINT32_MAX;check(act(s,0,Op::ready,{1})==Reject::exhausted);
 s=room();check(act(s,0,Op::ready,{1})==Reject::none);check(act(s,1,Op::ready,{1})==Reject::none);
 check(act(s,1,Op::loadout,{23})==Reject::none);check(s.ready==1&&s.planes[1].aircraft==23&&s.planes[0].aircraft==0);
 check(act(s,1,Op::ready,{1})==Reject::none);check(act(s,1,Op::loadout,{24})==Reject::none);check(s.ready==1);
 f=snapshot(s);f.args[36]=123;f.args[37]=1;f.args[38]=3;check(state_from(f,mirror));f.args[38]=7;check(!state_from(f,mirror));
 s=room();check(act(s,0,Op::select_mission,{6,1})==Reject::none);check(act(s,1,Op::loadout,{23})==Reject::none);
 check(act(s,0,Op::open_local_hangar)==Reject::not_ready);
 check(act(s,0,Op::ready,{1})==Reject::none);check(act(s,1,Op::ready,{1})==Reject::none);
 check(act(s,1,Op::open_local_hangar)==Reject::role);check(act(s,0,Op::open_local_hangar)==Reject::none);
 check(s.stage==Stage::hangar_loading&&s.ready==0);check(act(s,1,Op::ready,{1})==Reject::stage);
 check(act(s,0,Op::local_hangar_arrived,{23,24})==Reject::value);check(act(s,1,Op::local_hangar_arrived,{23,23})==Reject::role);
 check(act(s,0,Op::local_hangar_arrived,{23,23})==Reject::none);check(s.stage==Stage::hangar&&s.ready==0&&s.planes[0].aircraft==23);
 check(act(s,0,Op::start_sortie)==Reject::not_ready);check(act(s,1,Op::ready,{1})==Reject::none);check(act(s,0,Op::start_sortie)==Reject::not_ready);
 check(act(s,0,Op::ready,{1})==Reject::none);check(act(s,1,Op::start_sortie)==Reject::role);check(act(s,0,Op::start_sortie)==Reject::none);
 check(s.stage==Stage::flight_loading&&s.ready==0);check(act(s,1,Op::local_flight_arrived)==Reject::role);check(act(s,0,Op::local_flight_arrived)==Reject::none);
 check(s.stage==Stage::flight);check(act(s,0,Op::local_flight_arrived)==Reject::stage);
 printf("%u shared-session authority, phase barrier and wire checks passed\n",checks);
}
