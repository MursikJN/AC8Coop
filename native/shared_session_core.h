#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
// Pure host authority. Catalog IDs are protocol keys, never unverified engine offsets.
namespace ac8session {
enum class Stage:uint32_t { lobby=0,intro_loading=1,cutscene=2,hangar_loading=3,hangar=4,flight_loading=5,flight=6,result=7,stopped=8
#ifdef AC8_SESSION_POLICY_R29
 ,restart_loading=9,restart_exit=10
#endif
};
enum class Op:uint32_t { ready=1,select_mission=2,loadout=3,assign_wingman=4,vote_skip=5,start_sortie=6,loaded=7,scene_ended=8,begin_intro=9,open_local_hangar=10,local_hangar_arrived=11,local_flight_arrived=12
#ifdef AC8_MISSION_SYNC_R26
 ,commit=13,scene_segment=14,abort_session=15,begin_flight_scene=16
#ifdef AC8_STEAM_COOP_R27
 ,clock_ping=17,clock_reply=18
#ifdef AC8_CINEMA_SYNC_R28
 ,cinema_prepared=19,cinema_finished=20,cinema_commit=21
#ifdef AC8_SESSION_POLICY_R29
 ,restart=22,cancel=23,fault=24,restart_ack=25,mission_result=26,invalidate_ready=27
#endif
#endif
#endif
#endif
};
enum class Reject:uint32_t { none=0,role=1,stage=2,stale=3,value=4,not_ready=5,exhausted=6 };
#ifdef AC8_SESSION_POLICY_R29
using Args=std::array<uint32_t,64>;
enum class StopReason:uint32_t { none=0,cancelled=1,load_timeout=2,peer_lost=3,adapter_error=4 };
#else
using Args=std::array<uint32_t,48>;
#endif
struct Loadout {uint32_t aircraft=0,weapon1=0,weapon2=0,count=0;std::array<uint32_t,8> mods{};};
inline bool valid(const Loadout&v){
 if(v.aircraft>65535||v.weapon1>65535||v.weapon2>65535||v.count>8)return false;
 if(!v.aircraft&&(v.weapon1||v.weapon2||v.count))return false;
 for(size_t i=0;i<8;++i){if(i>=v.count){if(v.mods[i])return false;}else{if(!v.mods[i]||v.mods[i]>65535)return false;for(size_t j=0;j<i;++j)if(v.mods[i]==v.mods[j])return false;}}
 return true;
}
struct State {
 Stage stage=Stage::lobby;uint32_t epoch=1,revision=1,mission=0,difficulty=0,wingman=1;
 uint32_t ready=0,loaded=0,votes=0,scene=0,generation=0,changes=1;
#ifdef AC8_SESSION_POLICY_R29
 StopReason stop_reason=StopReason::none;uint32_t restart_id=0,restart_ack=0;
 bool accepts_join()const{return stage==Stage::lobby;}
 void fail(StopReason why){
  if(stage==Stage::stopped)return;
  stop_reason=why;reset_cinema();transition(Stage::stopped);
  if(generation<UINT32_MAX)++generation;if(changes<UINT32_MAX)++changes;
 }
#endif
#ifdef AC8_MISSION_SYNC_R26
 uint32_t committed=0,scene_exit=0,scene_return=3;uint64_t release_at=0;
#ifdef AC8_CINEMA_SYNC_R28
 // Every clip has its own barrier, including consecutive briefing clips.
 uint32_t cinema_prepared=0,cinema_finished=0,cinema_state=0,cinema_committed=0;uint64_t cinema_at=0;
 void reset_cinema(){cinema_prepared=cinema_finished=cinema_state=cinema_committed=0;cinema_at=0;}
 bool cinema_tick(uint64_t now){
  if(stage!=Stage::cutscene||cinema_prepared!=3)return false;
  if(changes==UINT32_MAX||now>UINT64_MAX-1500){stage=Stage::stopped;return true;}
  if(cinema_state==0||(cinema_state==2&&(cinema_finished==3||votes==3))){
   cinema_state=cinema_state==0?1:3;cinema_at=now+1500;cinema_committed=0;++changes;return true;
  }
  if(cinema_state!=1&&cinema_state!=3)return false;
  if(now<cinema_at)return false;
  if(cinema_committed!=3){cinema_at=now+1500;cinema_committed=0;++changes;return true;}
  ++cinema_state;cinema_at=0;cinema_committed=0;++changes;return true;
 }
#endif
 bool loading()const{return stage==Stage::intro_loading||stage==Stage::hangar_loading||stage==Stage::flight_loading
#ifdef AC8_SESSION_POLICY_R29
 ||stage==Stage::restart_loading
#endif
 ;}
 // Same-PC transport uses Windows' shared monotonic clock. Network clock
 // calibration is a separate client integration and is not inferred here.
 bool tick(uint64_t now){
  if(!loading()||loaded!=3)return false;
  if(changes==UINT32_MAX||epoch==UINT32_MAX||now>UINT64_MAX-1500){stage=Stage::stopped;return true;}
  if(!release_at||(now>=release_at&&committed!=3)){release_at=now+1500;committed=0;++changes;return true;}
  if(now<release_at)return false;
  transition(stage==Stage::intro_loading?Stage::cutscene:stage==Stage::hangar_loading?Stage::hangar:
#ifdef AC8_SESSION_POLICY_R29
   stage==Stage::restart_loading?Stage::restart_exit:
#endif
   Stage::flight);++changes;return true;
 }
#endif
 std::array<Loadout,2> planes{};
 bool can_intro()const{return stage==Stage::lobby&&mission&&ready==3;}
 bool can_sortie()const{return stage==Stage::hangar&&ready==3&&planes[0].aircraft&&planes[1].aircraft;}
 Reject apply(unsigned player,Op op,const Args&a,uint32_t expected_epoch,uint32_t expected_revision){
  if(player>1)return Reject::role;
  if(expected_epoch!=epoch||expected_revision!=revision){
#ifdef AC8_SESSION_POLICY_R29
   // A cancellation follows the same attempt across a loading transition,
   // but can never abort a later generation or changed configuration.
   if((op!=Op::cancel&&op!=Op::fault)||expected_epoch>epoch||expected_revision!=revision||a[0]!=generation)return Reject::stale;
#else
   return Reject::stale;
#endif
  }
  if(changes==UINT32_MAX||epoch==UINT32_MAX||revision==UINT32_MAX||generation==UINT32_MAX)return Reject::exhausted;
  const auto bit=1u<<player;
  switch(op){
   case Op::select_mission:
    if(player)return Reject::role;
    if(stage!=Stage::lobby)return Reject::stage;
    if(!a[0]||a[0]>65535||a[1]>255)return Reject::value;
#ifdef AC8_SESSION_POLICY_R29
    if(mission==a[0]&&difficulty==a[1])return Reject::none;
#endif
    mission=a[0];difficulty=a[1];++revision;ready=0;break;
   case Op::ready:
    if(stage!=Stage::lobby&&stage!=Stage::hangar)return Reject::stage;
    if(a[0]>1)return Reject::value;
    if(!mission||(stage==Stage::hangar&&!planes[player].aircraft))return Reject::not_ready;
    if(bool(ready&bit)==bool(a[0]))return Reject::none;
    ready=a[0]?(ready|bit):(ready&~bit);break;
   case Op::assign_wingman:
    if(player)return Reject::role;
    if(stage!=Stage::hangar)return Reject::stage;
    if(a[0]<1||a[0]>3)return Reject::value;
#ifdef AC8_SESSION_POLICY_R29
    if(wingman==a[0])return Reject::none;
#endif
    wingman=a[0];++revision;ready=0;break;
   case Op::loadout:{
    // Development lobby may preview a loadout; the in-game hangar still needs its adapter.
    if(stage!=Stage::hangar&&stage!=Stage::lobby)return Reject::stage;
    Loadout p;p.aircraft=a[0];p.weapon1=a[1];p.weapon2=a[2];p.count=a[3];for(size_t i=0;i<8;++i)p.mods[i]=a[4+i];
    if(!valid(p)||!p.aircraft)return Reject::value;
#ifdef AC8_SESSION_POLICY_R29
    const auto&old=planes[player];if(old.aircraft==p.aircraft&&old.weapon1==p.weapon1&&old.weapon2==p.weapon2&&old.count==p.count&&old.mods==p.mods)return Reject::none;
    ++revision; // Invalidates every in-flight intent from the previous loadout.
#endif
    planes[player]=p;ready&=~bit;break;
   }
   case Op::begin_intro:
    if(player)return Reject::role;
    if(!can_intro())return Reject::not_ready;
    if(!a[0])return Reject::value;
    scene=a[0];
#ifdef AC8_CINEMA_SYNC_R28
    reset_cinema();
#endif
#ifdef AC8_MISSION_SYNC_R26
    scene_exit=0;scene_return=3;
#endif
    transition(Stage::intro_loading);break;
   case Op::loaded:
#ifdef AC8_MISSION_SYNC_R26
    if(!loading())return Reject::stage;
#else
    if(stage!=Stage::intro_loading&&stage!=Stage::hangar_loading&&stage!=Stage::flight_loading)return Reject::stage;
#endif
#ifdef AC8_CINEMA_SYNC_R28
    if(stage==Stage::intro_loading&&!(cinema_prepared&bit))return Reject::not_ready;
#endif
#ifdef AC8_MISSION_SYNC_R26
    if(stage==Stage::hangar_loading&&!player&&!planes[0].aircraft)return Reject::not_ready;
#endif
    if(loaded&bit)return Reject::none;
    loaded|=bit;
#ifndef AC8_MISSION_SYNC_R26
    if(loaded==3)transition(stage==Stage::intro_loading?Stage::cutscene:stage==Stage::hangar_loading?Stage::hangar:Stage::flight);
#endif
    break;
   case Op::vote_skip:
    if(stage!=Stage::cutscene)return Reject::stage;
    if(a[0]!=scene)return Reject::stale;
    if(votes&bit)return Reject::none;
    votes|=bit;
#ifdef AC8_MISSION_SYNC_R26
    if(votes==3)scene_exit=1;
#else
    if(votes==3)transition(Stage::hangar_loading);
#endif
    break;
   case Op::scene_ended:
    if(player)return Reject::role;
    if(stage!=Stage::cutscene)return Reject::stage;
    if(a[0]!=scene)return Reject::stale;
#ifdef AC8_CINEMA_SYNC_R28
    if(cinema_state!=4||cinema_finished!=3)return Reject::not_ready;
#endif
#ifdef AC8_MISSION_SYNC_R26
    if(!scene_exit)scene_exit=2;
    transition(static_cast<Stage>(scene_return));break;
#else
    transition(Stage::hangar_loading);break;
#endif
   case Op::start_sortie:
    if(player)return Reject::role;
    if(!can_sortie())return Reject::not_ready;
    ++generation;transition(Stage::flight_loading);break;
   case Op::open_local_hangar:
#ifdef AC8_MISSION_SYNC_R26
    return Reject::stage; // Never bypass intro/barriers in the synchronized profile.
#else
    if(player)return Reject::role;
    if(!can_intro()||planes[1].aircraft!=23)return Reject::not_ready;
    if(mission!=6||difficulty!=1)return Reject::value;
    transition(Stage::hangar_loading);break;
#endif
   case Op::local_hangar_arrived:
    if(player)return Reject::role;
    if(stage!=Stage::hangar_loading)return Reject::stage;
    if(!a[0]||a[0]>65535||a[1]!=23||planes[1].aircraft!=23)return Reject::value;
#ifdef AC8_MISSION_SYNC_R26
    if(loaded&1)return planes[0].aircraft==a[0]?Reject::none:Reject::stale;
    planes[0].aircraft=a[0];loaded|=1;
#else
    planes[0].aircraft=a[0];transition(Stage::hangar);
#endif
    break;
   case Op::local_flight_arrived:
    if(player)return Reject::role;
    if(stage!=Stage::flight_loading)return Reject::stage;
    if(loaded&1)return Reject::none;
#ifdef AC8_MISSION_SYNC_R26
    loaded|=1;
#else
    transition(Stage::flight);
#endif
    break;
#ifdef AC8_MISSION_SYNC_R26
   case Op::commit:
    if(!loading()||loaded!=3||!release_at)return Reject::stage;
    if((uint64_t(a[0])|(uint64_t(a[1])<<32))!=release_at)return Reject::stale;
    if(committed&bit)return Reject::none;committed|=bit;break;
   case Op::scene_segment:
    if(player)return Reject::role;if(stage!=Stage::cutscene)return Reject::stage;
    if(a[0]<=scene)return a[0]==scene?Reject::none:Reject::stale;
#ifdef AC8_CINEMA_SYNC_R28
    if(cinema_state!=4||cinema_finished!=3)return Reject::not_ready;
    reset_cinema();
#endif
    scene=a[0];votes=0;scene_exit=0;++epoch;break;
   case Op::abort_session:
    if(player)return Reject::role;
#ifdef AC8_CINEMA_SYNC_R28
    reset_cinema();
#endif
    stage=Stage::stopped;loaded=ready=votes=committed=0;release_at=0;++epoch;break;
   case Op::begin_flight_scene:
    if(player)return Reject::role;if(stage!=Stage::flight&&stage!=Stage::hangar_loading)return Reject::stage;
    if(a[0]<=scene)return Reject::stale;
#ifdef AC8_CINEMA_SYNC_R28
    reset_cinema();
#endif
    scene=a[0];scene_return=static_cast<uint32_t>(stage);scene_exit=0;transition(Stage::cutscene);break;
#ifdef AC8_CINEMA_SYNC_R28
   case Op::cinema_prepared:
    if(stage!=Stage::intro_loading&&stage!=Stage::cutscene)return Reject::stage;
    if(a[0]!=scene)return Reject::stale;
    if(cinema_state>1)return (cinema_prepared&bit)?Reject::none:Reject::stage;
    if(cinema_prepared&bit)return Reject::none;cinema_prepared|=bit;break;
   case Op::cinema_finished:
    if(stage!=Stage::cutscene||cinema_state<2)return Reject::stage;
    if(a[0]!=scene)return Reject::stale;
    if(!(cinema_prepared&bit))return Reject::not_ready;
    if(cinema_finished&bit)return Reject::none;cinema_finished|=bit;break;
   case Op::cinema_commit:
    if(stage!=Stage::cutscene||(cinema_state!=1&&cinema_state!=3)||!cinema_at)return Reject::stage;
    if((uint64_t(a[0])|(uint64_t(a[1])<<32))!=cinema_at)return Reject::stale;
    if(cinema_committed&bit)return Reject::none;cinema_committed|=bit;break;
#ifdef AC8_SESSION_POLICY_R29
   case Op::restart:
    if(player)return Reject::role;
    if(a[0]!=generation)return Reject::stale;
    if(stage==Stage::lobby||stage==Stage::restart_loading||stage==Stage::restart_exit)return Reject::stage;
    if(!mission||restart_id==UINT32_MAX)return Reject::exhausted;
    ++restart_id;++generation;++revision;restart_ack=0;stop_reason=StopReason::none;scene=0;scene_exit=0;scene_return=3;reset_cinema();transition(Stage::restart_loading);break;
   case Op::cancel:
   case Op::fault:
    if(a[0]!=generation)return Reject::stale;
    if(stage==Stage::stopped)return Reject::none;
    if(stage==Stage::lobby||(stage==Stage::restart_exit&&restart_ack==2))return Reject::stage;
    fail(op==Op::cancel?StopReason::cancelled:StopReason::adapter_error);return Reject::none;
   case Op::restart_ack:
    if(!player)return Reject::role;
    if(stage!=Stage::restart_exit)return Reject::stage;
    if(a[0]!=restart_id)return Reject::stale;
    if(restart_ack==2)return Reject::none;restart_ack=2;break;
   case Op::mission_result:
    if(player)return Reject::role;
    if(stage!=Stage::flight)return Reject::stage;
    if(a[0]!=generation)return Reject::stale;
    reset_cinema();transition(Stage::result);break;
   case Op::invalidate_ready:
    if(player)return Reject::role;if(stage!=Stage::hangar)return Reject::stage;
    if(!ready)return Reject::none;ready=0;++revision;break;
#endif
#endif
#endif
   default:return Reject::value;
  }
  ++changes;return Reject::none;
 }
 void disconnect(){
#ifdef AC8_SESSION_POLICY_R29
  // The peer may close normally only after acknowledging a durable restart.
  if(stage==Stage::restart_exit&&restart_ack==2){ready=loaded=votes=0;return;}
  if(stage!=Stage::lobby){fail(StopReason::peer_lost);return;}
#endif
 if(stage!=Stage::lobby)stage=Stage::stopped;ready=loaded=votes=0;
#ifdef AC8_CINEMA_SYNC_R28
 reset_cinema();
#endif
#ifdef AC8_MISSION_SYNC_R26
 committed=0;release_at=0;
#endif
 if(epoch<UINT32_MAX)++epoch;if(changes<UINT32_MAX)++changes;}
 private:void transition(Stage next){stage=next;++epoch;ready=loaded=votes=0;
#ifdef AC8_MISSION_SYNC_R26
 committed=0;release_at=0;
#endif
 }
};
inline bool valid(const State&s){return static_cast<uint32_t>(s.stage)<=
#ifdef AC8_SESSION_POLICY_R29
 10&&static_cast<uint32_t>(s.stop_reason)<=4&&(s.restart_ack==0||s.restart_ack==2)&&(!s.restart_ack||(s.stage==Stage::restart_exit&&s.restart_id))&&((s.stage!=Stage::restart_loading&&s.stage!=Stage::restart_exit)||s.restart_id)&&
#else
 8&&
#endif
 s.epoch&&s.revision&&s.changes&&s.mission<=65535&&s.difficulty<=255&&s.wingman>=1&&s.wingman<=3&&s.ready<=3&&s.loaded<=3&&s.votes<=3&&valid(s.planes[0])&&valid(s.planes[1])
#ifdef AC8_CINEMA_SYNC_R28
 &&s.cinema_prepared<=3&&s.cinema_finished<=3&&!(s.cinema_finished&~s.cinema_prepared)&&s.cinema_state<=4&&s.cinema_committed<=3
 &&(s.cinema_state==1||s.cinema_state==3? s.cinema_at!=0:s.cinema_at==0&&s.cinema_committed==0)
 &&(!s.cinema_state||s.cinema_prepared==3)
#endif
 ;}
}
