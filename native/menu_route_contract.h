#pragma once
#include <cstdint>
#include <cstring>
#include <string>
namespace ac8route {
struct Target {uintptr_t table=0,confirm=0;const char*fingerprint=nullptr;const char*tag=nullptr;int aircraft=-1;bool single_weapon=false;bool caption=false;int mission=-1;uintptr_t continuation=0;const char*continuation_fingerprint=nullptr;unsigned weapon_value=0;int edit_slot=-1;};
inline Target target(const std::string&kind){
 if(kind=="aircraft_f14")return {0xc81d2b0,0x7af0610,"4055565741574881ec88000000488b01",nullptr,23010,false};
 if(kind=="aircraft_host_f14"){auto t=target("aircraft_f14");t.edit_slot=0;return t;}
 if(kind=="aircraft_guest_f14"){auto t=target("aircraft_f14");t.edit_slot=1;return t;}
 if(kind=="squad_guest_aircraft")return {0xc815438,0x7af9630,"48894c24085553565741554156415748","SelectAircraft",-1,false};
 if(kind=="weapon1_guest_default")return target("weapon1_default");
 if(kind=="weapon2_guest_none")return target("weapon2_none");
 if(kind=="main_campaign")return {0xc82cf38,0x7b4ff50,"48895c241855565741564157488d6c24","CampaignTop",-1,false};
 if(kind=="campaign_continue")return {0xc7f05b0,0x7b13100,"4055574156488d6c24b94881ecf00000","Continue",-1,false,true};
 if(kind=="campaign_free_mission")return {0xc7f05b0,0x7b13100,"4055574156488d6c24b94881ecf00000","CampaignFreeMissionDifficulty",-1,false};
 if(kind=="difficulty_pilot")return {0xc7f6630,0x7ac98e0,"488bc45553488d68a14881ec88000000","Easy",-1,false,true,-1,0x7ac9d00,"48895c24084889742410574883ec3048"};
 if(kind=="mission6")return {0xc7f5c20,0x7b10e20,"405557488d6c24b14881eca800000048",nullptr,-1,false,false,7};
 if(kind=="narrative")return {0xc7efc38,0x7b114c0,"40555357488bec4883ec30488bf9488b","Narrative",-1,false,true};
 if(kind=="briefing_hangar")return {0xc7f7ba0,0x16b43e0,"32c0c3cccccccccccccccccccccccccc",nullptr,-1,true,false,-1,0x7a940a0,"40564883ec5080b9e006000000488bf1"};
 if(kind=="hangar_aircraft")return {0xc80f698,0x7afd080,"4055534154488d6c24b94881ecb00000","SelectAircraft",-1,false};
 if(kind=="weapon1_default")return {0xc8109e8,0x7aff250,"40555357488d6c24b94881ecb0000000",nullptr,-1,true,false,-1,0,nullptr,16};
 if(kind=="weapon2_none")return {0xc811bd0,0x7affdd0,"48895c2410488974241855574156488d","WID_NONE",-1,false,true};
 if(kind=="squad_standby")return {0xc815438,0x7af9630,"48894c24085553565741554156415748","Standby",-1,false};
 if(kind=="sortie")return {0xc815d90,0x7afb890,"48895c24184889742420555741544156","Sortie",-1,false};
 return {};
}
inline bool matches(const Target&t,const std::string&tag,int aircraft,unsigned weapon,int count,int index,int mission=-1){
 if(!t.table||index<0||index>=count||count>128)return false;
 // The uninitialized title bypass exposes only five main commands. The loaded
 // profile observed for this mission has six, including campaign training.
 if(t.table==0xc82cf38&&count!=6)return false;
 if(t.tag)return tag==t.tag;
 if(t.aircraft>=0)return aircraft==t.aircraft;
 if(t.mission>=0)return mission==t.mission;
 return t.single_weapon&&count==1&&index==0&&weapon==t.weapon_value;
}
inline bool fingerprint(const unsigned char*bytes,const char*hex){
 if(!bytes||!hex||std::strlen(hex)!=32)return false;
 auto digit=[](char c)->int{if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;return -1;};
 for(unsigned i=0;i<16;++i){int a=digit(hex[2*i]),b=digit(hex[2*i+1]);if(a<0||b<0||bytes[i]!=(a*16+b))return false;}return true;
}
}
