#pragma once
#include "shared_session_core.h"
namespace ac8session {
// Never use game time for a stalled load: that world may already be paused.
struct Watchdog {
 static constexpr uint64_t limit_ms=120000;
 uint64_t since=0;std::array<uint32_t,9> previous{};bool armed=false;
 static bool waiting(const State&s){return(s.loading()&&(s.stage!=Stage::hangar_loading||s.loaded==3))||(s.stage==Stage::restart_exit&&s.restart_ack!=2)||(s.stage==Stage::cutscene&&(s.cinema_state<2||s.cinema_state==3||(s.cinema_finished!=0&&s.cinema_finished!=3)));}
 bool tick(State&s,uint64_t now){
  if(!waiting(s)){armed=false;return false;}
  // Deadline rearming and heartbeat traffic are not loading progress.
  std::array<uint32_t,9> key{uint32_t(s.stage),s.generation,s.revision,s.scene,s.loaded,s.committed,s.cinema_prepared,s.cinema_finished,s.cinema_state};
  // Partial commits may oscillate on rearming; do not extend on them.
  key[5]=0;
  if(!armed||key!=previous){previous=key;since=now;armed=true;return false;}
  if(now<since||now-since<limit_ms)return false;
  s.fail(StopReason::load_timeout);armed=false;return true;
 }
 uint64_t remaining(uint64_t now)const{return !armed?0:now<since?limit_ms:now-since>=limit_ms?0:limit_ms-(now-since);}
};
}
