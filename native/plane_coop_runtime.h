#pragma once
#include "plane_coop_transport.h"
namespace ac8flight {
struct Runtime {
 PeerGate gate{};Frame local{};
 bool configured=false,armed=false,stopped=false,had_transport=false;
 uint64_t born_us=0,armed_ms=0,last_send_ms=0,last_status_ms=0,applied_sequence=0,receiver_timestamp=0;
 unsigned sent=0,accepted=0,rejected=0;
 const char* detail="not_preflighted";
};
inline bool materialize_remote(Runtime& runtime,const plane_initial_state::Snapshot& local,plane_initial_state::Snapshot& out){
 if(!local.complete||!local.timestamp||!runtime.gate.have_peer||runtime.gate.terminal||runtime.stopped)return false;
 if(runtime.applied_sequence!=runtime.gate.peer.sequence){runtime.applied_sequence=runtime.gate.peer.sequence;runtime.receiver_timestamp=local.timestamp;}
 out=runtime.gate.peer.state;out.source=local.source;out.image=local.image;out.token=local.token;
 out.timestamp=runtime.receiver_timestamp;out.scale=local.scale;out.complete=true;plane_initial_state::put(out.main,8,out.timestamp);return true;
}
}
