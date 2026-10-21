#define AC8_STEAM_COOP_R27
#define AC8_MISSION_SYNC_R26
#include "shared_session_protocol.h"
#include "steam_coop_clock.h"
#include "steam_invite_core.h"
#include "coop_skip_input.h"
#include "guest_pilot_protocol.h"
#include <cassert>
#include <cstdio>
int main(){
 ac8coop::SkipHold key;assert(!key.sample(1,true,false,2,1));assert(!key.sample(10,true,true,2,1));assert(!key.sample(709,true,true,2,1));assert(key.sample(710,true,true,2,1));assert(!key.sample(720,true,true,2,1));assert(!key.sample(900,true,true,2,2));assert(!key.sample(2000,true,true,2,2));assert(!key.sample(2010,true,false,2,2));assert(!key.sample(2020,true,true,2,2));assert(key.sample(2720,true,true,2,2));
 ac8pilot::Frame state;state.sender=1;state.session=2;state.echo=3;state.sequence=1;state.generation=1;state.source_us=1;state.count=4;state.flags=ac8pilot::flight_only|ac8pilot::loaded_ack;
 for(unsigned i=0;i<4;++i){auto&p=state.poses[i];p.role=i;p.aircraft=i==1?23:7;p.max_health=p.health=200;p.rotation={0,0,0,1};}
 auto pilot=ac8pilot::encode(state);ac8pilot::Frame pilot_decoded;assert(ac8pilot::decode(pilot.data(),pilot.size(),pilot_decoded));pilot[4]=1;assert(!ac8pilot::decode(pilot.data(),pilot.size(),pilot_decoded));
 ac8coop::Clock c;c.begin(1000);assert(!c.accept(999,10000,1020));assert(!c.ready(1020));
 assert(c.accept(1000,10010,1020));assert(!c.ready(1020));c.begin(1750);assert(c.accept(1750,10760,1770));assert(c.ready(1770));assert(c.host_now(1770)==10770);assert(!c.ready(4771));
 c.begin(5000);assert(!c.accept(5000,14010,5300));c.reset();assert(!c.ready(5300));
 auto id=76561198000000001ull;auto invite=ac8invite::encode(id);assert(invite.find("ac8coop:v5:")==0);uint64_t host=0;assert(ac8invite::decode(invite.c_str(),invite.size()+1,host)&&host==id);
 ac8session::Frame f;f.sender=1;f.session=2;f.echo=3;f.sequence=4;f.op=ac8session::Op::clock_reply;f.args[0]=123;f.args[2]=999;
 auto b=ac8session::encode(f);ac8session::Frame decoded;assert(ac8session::decode(b.data(),b.size(),decoded));b[4]=4;assert(!ac8session::decode(b.data(),b.size(),decoded));
 ac8session::State s;ac8session::Args a{};a[0]=6;a[1]=1;assert(s.apply(0,ac8session::Op::select_mission,a,s.epoch,s.revision)==ac8session::Reject::none);
 a={};a[0]=1;for(unsigned p=0;p<2;++p)assert(s.apply(p,ac8session::Op::ready,a,s.epoch,s.revision)==ac8session::Reject::none);
 assert(s.apply(1,ac8session::Op::begin_intro,a,s.epoch,s.revision)==ac8session::Reject::role);
 assert(s.apply(0,ac8session::Op::begin_intro,a,s.epoch,s.revision)==ac8session::Reject::none);a={};
 for(unsigned p=0;p<2;++p)assert(s.apply(p,ac8session::Op::loaded,a,s.epoch,s.revision)==ac8session::Reject::none);
 assert(s.tick(10000));assert(s.release_at==11500);a[0]=11500;
 for(unsigned p=0;p<2;++p)assert(s.apply(p,ac8session::Op::commit,a,s.epoch,s.revision)==ac8session::Reject::none);
 assert(!s.tick(11499));assert(s.tick(11500)&&s.stage==ac8session::Stage::cutscene);a={};a[0]=1;
 assert(s.apply(1,ac8session::Op::scene_ended,a,s.epoch,s.revision)==ac8session::Reject::role);
 s.disconnect();assert(s.stage==ac8session::Stage::stopped&&s.ready==0);puts("Steam coop clock, invitation, protocol and host barriers passed");
}
