#define AC8_STEAM_COOP_R27
#define AC8_MISSION_SYNC_R26
#define AC8_CINEMA_SYNC_R28
#include "shared_session_protocol.h"
#include "cinema_descriptor.h"
#include "steam_invite_core.h"
#include <cassert>
#include <cstdio>
using namespace ac8session;
static unsigned checks=0;
static void expect(bool v){++checks;assert(v);}
static Reject apply(State&s,unsigned p,Op op,uint32_t a=0,uint32_t b=0){Args args{};args[0]=a;args[1]=b;return s.apply(p,op,args,s.epoch,s.revision);}
static void roundtrip(const State&s){auto f=snapshot(s);f.sender=1;f.session=2;f.echo=3;f.sequence=1;auto bytes=encode(f);Frame d;State out;expect(decode(bytes.data(),bytes.size(),d));expect(state_from(d,out));expect(out.cinema_state==s.cinema_state&&out.cinema_finished==s.cinema_finished&&out.cinema_at==s.cinema_at);}
int main(){
 State s;s.stage=Stage::intro_loading;s.scene=1;s.mission=6;s.difficulty=1;
 expect(apply(s,1,Op::loaded)==Reject::not_ready);
 for(unsigned p=0;p<2;++p){expect(apply(s,p,Op::cinema_prepared,1)==Reject::none);expect(apply(s,p,Op::loaded)==Reject::none);}
 expect(s.tick(1000));for(unsigned p=0;p<2;++p)expect(apply(s,p,Op::commit,2500)==Reject::none);expect(s.tick(2500)&&s.stage==Stage::cutscene);
 expect(s.cinema_prepared==3);expect(s.cinema_tick(2500)&&s.cinema_at==4000);roundtrip(s);
 expect(apply(s,0,Op::cinema_commit,4000)==Reject::none);expect(s.cinema_tick(4000)&&s.cinema_state==1&&s.cinema_at==5500);
 expect(apply(s,1,Op::cinema_commit,4000)==Reject::stale);
 for(unsigned p=0;p<2;++p)expect(apply(s,p,Op::cinema_commit,5500)==Reject::none);
 expect(!s.cinema_tick(5499));expect(s.cinema_tick(5500)&&s.cinema_state==2);roundtrip(s);
 // Host finishes early; it cannot travel, or start a subsequent clip.
 expect(apply(s,0,Op::cinema_finished,1)==Reject::none);const auto changes=s.changes;
 for(unsigned i=0;i<100;++i)expect(!s.cinema_tick(6000+i));
 expect(apply(s,0,Op::scene_ended,1)==Reject::not_ready);expect(apply(s,0,Op::scene_segment,2)==Reject::not_ready);
 expect(apply(s,0,Op::cinema_finished,1)==Reject::none&&s.changes==changes);
 expect(apply(s,1,Op::cinema_finished,0)==Reject::stale);expect(apply(s,1,Op::scene_ended,1)==Reject::role);
 expect(apply(s,1,Op::cinema_finished,1)==Reject::none);expect(s.cinema_tick(10000)&&s.cinema_state==3);
 for(unsigned p=0;p<2;++p)expect(apply(s,p,Op::cinema_commit,11500)==Reject::none);expect(s.cinema_tick(11500)&&s.cinema_state==4);roundtrip(s);
 auto old_epoch=s.epoch;expect(apply(s,0,Op::scene_segment,2)==Reject::none);expect(!s.cinema_finished&&!s.cinema_prepared&&!s.cinema_state&&!s.votes);
 Args stale{};stale[0]=2;expect(s.apply(1,Op::cinema_prepared,stale,old_epoch,s.revision)==Reject::stale);
 for(unsigned p=0;p<2;++p)expect(apply(s,p,Op::cinema_prepared,2)==Reject::none);expect(s.cinema_tick(12000));
 for(unsigned p=0;p<2;++p)expect(apply(s,p,Op::cinema_commit,13500)==Reject::none);expect(s.cinema_tick(13500));
 expect(apply(s,0,Op::vote_skip,2)==Reject::none);expect(!s.cinema_tick(14000)&&s.cinema_state==2);
 expect(apply(s,1,Op::vote_skip,2)==Reject::none);expect(s.cinema_tick(14001)&&s.cinema_state==3);
 // A skip also needs both acknowledgement receipts, then actual local stops.
 expect(apply(s,0,Op::cinema_commit,15501)==Reject::none);expect(s.cinema_tick(15501)&&s.cinema_at==17001);
 for(unsigned p=0;p<2;++p)expect(apply(s,p,Op::cinema_commit,17001)==Reject::none);expect(s.cinema_tick(17001));
 expect(apply(s,0,Op::scene_ended,2)==Reject::not_ready);
 for(unsigned p=0;p<2;++p)expect(apply(s,p,Op::cinema_finished,2)==Reject::none);
 expect(apply(s,0,Op::scene_ended,2)==Reject::none&&s.stage==Stage::hangar_loading);roundtrip(s);
 s.disconnect();expect(s.stage==Stage::stopped&&!s.cinema_state&&!s.cinema_finished);roundtrip(s);
 ac8cinema::Descriptor d;d.sender=1;d.session=2;d.echo=3;d.sequence=1;d.epoch=1;d.revision=2;d.scene=3;d.kind=1;d.duration_ms=50000;d.asset="/Game/Movies/Movie.Movie";d.viewer="/Game/UI/Viewer.Viewer_C";
 auto bytes=ac8cinema::encode(d);ac8cinema::Descriptor out;expect(ac8cinema::decode(bytes.data(),bytes.size(),out)&&out.asset==d.asset);
 for(size_t offset:{size_t(4),size_t(12),size_t(68),size_t(511),size_t(1535)}){auto bad=bytes;bad[offset]=255;expect(!ac8cinema::decode(bad.data(),bad.size(),out));}
 expect(!ac8cinema::path("/Game/../bad"));expect(!ac8cinema::path("http://example.com/movie"));expect(!ac8cinema::path("/Game/Asset\ncommand"));
 expect(ac8invite::encode(76561198000000001ull).find("ac8coop:v6:")==0);
 printf("Cinema per-clip loading, delayed peer, two-vote skip, completion, replay and descriptor: %u checks passed\n",checks);
}
