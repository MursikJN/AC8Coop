#include "adapter_bootstrap_contract.h"
#include "menu_route_contract.h"
#include <array>
#include <cassert>
#include <cstdio>
int main(){
 unsigned checks=0;auto check=[&](bool ok){assert(ok);++checks;};
 const std::array<unsigned char,16> actual={0x40,0x57,0x48,0x83,0xec,0x20,0x80,0x79,0x38,0x00,0x48,0x8b,0xf9,0x0f,0x84,0x9b};
 check(ac8route::fingerprint(actual.data(),ac8adapter::pause_update_fingerprint));
 check(!ac8route::fingerprint(actual.data(),"40574883ec2080793800488bf90f849b00"));
 auto wrong=actual;wrong[0]^=1;check(!ac8route::fingerprint(wrong.data(),ac8adapter::pause_update_fingerprint));
 check(ac8adapter::pause_protocol==2);
 for(const auto kind:{"main_campaign","campaign_free_mission","difficulty_pilot","mission6","narrative","briefing_hangar","hangar_aircraft","aircraft_guest_f14","squad_guest_aircraft","squad_standby","sortie"}){
  const auto target=ac8route::target(kind);check(target.table!=0&&std::strlen(target.fingerprint)==32);
  if(target.continuation)check(target.continuation_fingerprint&&std::strlen(target.continuation_fingerprint)==32);
 }
 printf("%u adapter bootstrap contract checks passed; no game calls\n",checks);
}
