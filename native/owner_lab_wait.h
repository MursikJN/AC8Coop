#pragma once
#include <cstdint>
namespace ac8owner {
// Local protocol helper only. No packet/version change or premature loaded ack.
struct LabWait {
 static constexpr uint64_t preparation_ms=60000,flight_idle_ms=15000;
 uint64_t connected_at=0;bool connected=false,loaded=false;
 void observe_connection(uint64_t now){if(!connected){connected=true;connected_at=now;}}
 bool expired(uint64_t now)const{return connected&&!loaded&&(now<connected_at||now-connected_at>=preparation_ms);}
 uint64_t idle_budget()const{return loaded?flight_idle_ms:preparation_ms;}
};
}
