#pragma once
#include "connection_protocol.h"
#include "shared_session_core.h"
namespace ac8session {
#ifdef AC8_SESSION_POLICY_R29
constexpr size_t packet_size=320;
#ifdef AC8_OWNER_SIM_R30
constexpr unsigned protocol_version=8;
#else
constexpr unsigned protocol_version=7;
#endif
#else
constexpr size_t packet_size=256;
#ifdef AC8_CINEMA_SYNC_R28
constexpr unsigned protocol_version=6;
#elif defined(AC8_STEAM_COOP_R27)
constexpr unsigned protocol_version=5;
#elif defined(AC8_MISSION_SYNC_R26)
constexpr unsigned protocol_version=4;
#elif defined(AC8_STEAM_LOBBY_R24)
constexpr unsigned protocol_version=3;
#else
constexpr unsigned protocol_version=2;
#endif
#endif
enum class Kind:uint32_t { snapshot=1,intent=2,keepalive=3 };
struct Frame {Kind kind=Kind::intent;uint64_t sender=0,session=0,echo=0,sequence=0;uint32_t epoch=1,revision=1;Op op=Op::ready;Args args{};};
inline bool valid(const Frame&f){
 if(!f.sender||!f.session||!f.echo||!f.sequence||!f.epoch||!f.revision)return false;
 if(f.kind==Kind::keepalive){if(static_cast<uint32_t>(f.op))return false;for(auto v:f.args)if(v)return false;return true;}
 if(f.kind==Kind::snapshot)return static_cast<uint32_t>(f.op)==0;
 if(f.kind!=Kind::intent)return false;
 auto op=static_cast<uint32_t>(f.op);
#ifdef AC8_SESSION_POLICY_R29
 if(op<1||op>27)return false;
#elif defined(AC8_CINEMA_SYNC_R28)
 if(op<1||op>21)return false;
#elif defined(AC8_STEAM_COOP_R27)
 if(op<1||op>18)return false;
#elif defined(AC8_MISSION_SYNC_R26)
 if(op<1||op>16)return false;
#else
 if(op<1||op>12)return false;
#endif
 size_t used=f.op==Op::loadout?12:(f.op==Op::select_mission||f.op==Op::local_hangar_arrived)?2:(f.op==Op::ready||f.op==Op::assign_wingman||f.op==Op::vote_skip||f.op==Op::scene_ended||f.op==Op::begin_intro)?1:0;
#ifdef AC8_MISSION_SYNC_R26
 if(f.op==Op::commit)used=2;if(f.op==Op::scene_segment||f.op==Op::begin_flight_scene)used=1;
#ifdef AC8_STEAM_COOP_R27
 if(f.op==Op::clock_ping)used=2;if(f.op==Op::clock_reply)used=4;
#ifdef AC8_CINEMA_SYNC_R28
 if(f.op==Op::cinema_prepared||f.op==Op::cinema_finished)used=1;
 if(f.op==Op::cinema_commit)used=2;
#ifdef AC8_SESSION_POLICY_R29
 if(f.op==Op::restart||f.op==Op::cancel||f.op==Op::fault||f.op==Op::restart_ack||f.op==Op::mission_result)used=1;
#endif
#endif
#endif
#endif
 for(size_t i=used;i<f.args.size();++i)if(f.args[i])return false;
 return true;
}
inline std::array<uint8_t,packet_size> encode(const Frame&f){
 std::array<uint8_t,packet_size>b{};memcpy(b.data(),"AC8S",4);ac8test::put(b.data()+4,protocol_version,2);ac8test::put(b.data()+6,packet_size,2);ac8test::put(b.data()+8,ac8test::build,4);ac8test::put(b.data()+12,static_cast<uint32_t>(f.kind),4);
 size_t n=16;for(auto v:{f.sender,f.session,f.echo,f.sequence}){ac8test::put(b.data()+n,v,8);n+=8;}
 ac8test::put(b.data()+48,f.epoch,4);ac8test::put(b.data()+52,f.revision,4);ac8test::put(b.data()+56,static_cast<uint32_t>(f.op),4);
 for(size_t i=0;i<f.args.size();++i)ac8test::put(b.data()+64+4*i,f.args[i],4);return b;
}
inline bool decode(const void*p,size_t length,Frame&f){
 if(!p||length!=packet_size)return false;auto b=static_cast<const uint8_t*>(p);
 if(memcmp(b,"AC8S",4)||ac8test::get(b+4,2)!=protocol_version||ac8test::get(b+6,2)!=packet_size||ac8test::get(b+8,4)!=ac8test::build||ac8test::get(b+60,4))return false;
 f={};f.kind=static_cast<Kind>(ac8test::get(b+12,4));size_t n=16;for(auto id:{&f.sender,&f.session,&f.echo,&f.sequence}){*id=ac8test::get(b+n,8);n+=8;}
 f.epoch=static_cast<uint32_t>(ac8test::get(b+48,4));f.revision=static_cast<uint32_t>(ac8test::get(b+52,4));f.op=static_cast<Op>(ac8test::get(b+56,4));
 for(size_t i=0;i<f.args.size();++i)f.args[i]=static_cast<uint32_t>(ac8test::get(b+64+4*i,4));return valid(f);
}
inline Frame snapshot(const State&s){
 Frame f;f.kind=Kind::snapshot;f.op=static_cast<Op>(0);f.epoch=s.epoch;f.revision=s.revision;
 f.args[0]=static_cast<uint32_t>(s.stage);f.args[1]=s.mission;f.args[2]=s.difficulty;f.args[3]=s.wingman;f.args[4]=s.ready;f.args[5]=s.loaded;f.args[6]=s.votes;f.args[7]=s.scene;f.args[8]=s.generation;f.args[9]=s.changes;
#ifdef AC8_MISSION_SYNC_R26
 f.args[10]=s.scene_exit;f.args[11]=s.committed;f.args[39]=uint32_t(s.release_at);f.args[40]=uint32_t(s.release_at>>32);f.args[41]=s.scene_return;
#ifdef AC8_CINEMA_SYNC_R28
 f.args[42]=s.cinema_prepared;f.args[43]=s.cinema_finished;f.args[44]=s.cinema_state;f.args[45]=s.cinema_committed;f.args[46]=uint32_t(s.cinema_at);f.args[47]=uint32_t(s.cinema_at>>32);
#ifdef AC8_SESSION_POLICY_R29
 f.args[48]=uint32_t(s.stop_reason);f.args[49]=s.restart_id;f.args[50]=s.restart_ack;
#endif
#endif
#endif
 for(size_t p=0;p<2;++p){size_t n=12+12*p;const auto&v=s.planes[p];f.args[n]=v.aircraft;f.args[n+1]=v.weapon1;f.args[n+2]=v.weapon2;f.args[n+3]=v.count;for(size_t i=0;i<8;++i)f.args[n+4+i]=v.mods[i];}return f;
}
inline bool state_from(const Frame&f,State&s){
 if(f.kind!=Kind::snapshot||f.args[38]>6)return false;
#ifdef AC8_SESSION_POLICY_R29
 for(size_t i=51;i<64;++i)if(f.args[i])return false;
#endif
#ifdef AC8_MISSION_SYNC_R26
 if(f.args[10]>2||f.args[11]>3)return false;
 if(f.args[41]!=3&&f.args[41]!=6)return false;
#ifndef AC8_CINEMA_SYNC_R28
 for(size_t i=42;i<48;++i)if(f.args[i])return false;
#endif
#else
 if(f.args[10]||f.args[11])return false;
 // Local bridge may return the last guest intent sequence (36/37) and rejection (38).
 for(size_t i=39;i<48;++i)if(f.args[i])return false;
#endif
 s={};s.stage=static_cast<Stage>(f.args[0]);s.epoch=f.epoch;s.revision=f.revision;s.mission=f.args[1];s.difficulty=f.args[2];s.wingman=f.args[3];s.ready=f.args[4];s.loaded=f.args[5];s.votes=f.args[6];s.scene=f.args[7];s.generation=f.args[8];s.changes=f.args[9];
#ifdef AC8_MISSION_SYNC_R26
 s.scene_exit=f.args[10];s.committed=f.args[11];s.release_at=uint64_t(f.args[39])|(uint64_t(f.args[40])<<32);s.scene_return=f.args[41];
#ifdef AC8_CINEMA_SYNC_R28
 s.cinema_prepared=f.args[42];s.cinema_finished=f.args[43];s.cinema_state=f.args[44];s.cinema_committed=f.args[45];s.cinema_at=uint64_t(f.args[46])|(uint64_t(f.args[47])<<32);
#ifdef AC8_SESSION_POLICY_R29
 s.stop_reason=static_cast<StopReason>(f.args[48]);s.restart_id=f.args[49];s.restart_ack=f.args[50];
#endif
#endif
 if((s.committed&&!s.release_at)||(s.release_at&&(!s.loading()||s.loaded!=3)))return false;
#endif
 for(size_t p=0;p<2;++p){size_t n=12+12*p;auto&v=s.planes[p];v.aircraft=f.args[n];v.weapon1=f.args[n+1];v.weapon2=f.args[n+2];v.count=f.args[n+3];for(size_t i=0;i<8;++i)v.mods[i]=f.args[n+4+i];}return valid(s);
}
}
