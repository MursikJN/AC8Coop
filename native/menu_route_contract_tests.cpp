#include "menu_route_contract.h"
#include <cstdio>
#include <cstdlib>
unsigned checks=0;
void check(bool ok){++checks;if(!ok){std::fprintf(stderr,"Menu route check failed %u\n",checks);std::exit(1);}}
int main(){
 using namespace ac8route;
 // These tags and inventory rows were captured from the live stock menu.
 auto main=target("main_campaign");
 check(matches(main,"CampaignTop",-1,0,6,0));
 check(!matches(main,"CampaignTop",-1,0,5,0));
 check(!target("title_enter").table);
 for(auto tag:{"QuitGame","SystemTop","Shop","Online","CampaignTraining",""})check(!matches(main,tag,-1,0,6,0));
 auto free=target("campaign_free_mission");check(matches(free,"CampaignFreeMissionDifficulty",-1,0,5,2));check(!matches(free,"Restart",-1,0,5,0));
 auto resume=target("campaign_continue");check(resume.caption&&matches(resume,"Continue",-1,0,5,1));check(!matches(resume,"Restart",-1,0,5,0));
 auto difficulty=target("difficulty_pilot");check(difficulty.caption&&matches(difficulty,"Easy",-1,0,4,1));check(!matches(difficulty,"Hard",-1,0,4,3));
 auto aircraft=target("aircraft_f14");check(matches(aircraft,"",23010,0,12,2));
 for(auto model:{7010,13010,4010,22010,5010,6010,32010,24010,14010,15010,16010,23011,-1})check(!matches(aircraft,"",model,0,12,2));
 check(!matches(aircraft,"",23010,0,12,12));check(!matches(aircraft,"",23010,0,129,2));check(!matches(aircraft,"",23010,0,12,-1));
 auto weapon=target("weapon1_default");check(matches(weapon,"",-1,16,1,0));check(!matches(weapon,"",-1,0,1,0));check(!matches(weapon,"",-1,16,2,0));
 auto narrative=target("narrative");check(matches(narrative,"Narrative",-1,0,2,0));check(!matches(narrative,"AllAircraftSelect",-1,0,2,1));
 auto hangar=target("hangar_aircraft");check(matches(hangar,"SelectAircraft",-1,0,7,0));check(!matches(hangar,"SelectTraining",-1,0,7,5));
 auto sortie=target("sortie");check(matches(sortie,"Sortie",-1,0,7,0));check(!matches(sortie,"Top",-1,0,7,6));
 auto none=target("weapon2_none");check(matches(none,"WID_NONE",-1,16,1,0));check(!matches(none,"LAAM",-1,16,1,0));
 check(!target("quit_game").table);
 auto mission=target("mission6");check(matches(mission,"",-1,0,34,6,7));check(!matches(mission,"",-1,0,34,5,6));check(!matches(mission,"",-1,0,34,7,8));
 unsigned char bytes[]={0x40,0x55,0x56,0x57,0x41,0x57,0x48,0x81,0xec,0x88,0,0,0,0x48,0x8b,0x01};
 check(fingerprint(bytes,aircraft.fingerprint));bytes[0]=0x55;check(!fingerprint(bytes,aircraft.fingerprint));check(!fingerprint(bytes,"0"));
 auto host_plane=target("aircraft_host_f14"),guest_plane=target("aircraft_guest_f14");
 check(host_plane.edit_slot==0&&guest_plane.edit_slot==1);check(host_plane.table==guest_plane.table&&host_plane.confirm==guest_plane.confirm);
 check(matches(target("squad_guest_aircraft"),"SelectAircraft",-1,0,4,0));check(!matches(target("squad_guest_aircraft"),"Standby",-1,0,4,0));
 check(matches(target("weapon1_guest_default"),"",-1,16,1,0));check(matches(target("weapon2_guest_none"),"WID_NONE",-1,16,1,0));
 std::printf("%u menu command contract checks passed; no game calls\n",checks);
}
