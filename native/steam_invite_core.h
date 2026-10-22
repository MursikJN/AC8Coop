#pragma once
#include <cstdint>
#include <cstring>
#include <string>
// Private, versioned connect string. Never an engine URL or console command.
namespace ac8invite {
#ifdef AC8_OWNER_SIM_R30
constexpr char prefix[]="ac8coop:v8:25201480:";
#elif defined(AC8_SESSION_POLICY_R29)
constexpr char prefix[]="ac8coop:v7:25201480:";
#elif defined(AC8_CINEMA_SYNC_R28)
constexpr char prefix[]="ac8coop:v6:25201480:";
#elif defined(AC8_STEAM_COOP_R27)
constexpr char prefix[]="ac8coop:v5:25201480:";
#else
constexpr char prefix[]="ac8coop:v3:25201480:";
#endif
constexpr size_t value_capacity=256;
inline bool individual(uint64_t id){return(id>>56)==1&&((id>>52)&15)==1&&((id>>32)&0xfffff)==1&&uint32_t(id)!=0;}
inline std::string encode(uint64_t host){return individual(host)?std::string(prefix)+std::to_string(host):std::string();}
inline bool decode(const char*text,size_t capacity,uint64_t&host){
 host=0;if(!text||capacity>value_capacity)return false;
 const size_t size=sizeof(prefix)-1+17;
 if(capacity<=size||std::memcmp(text,prefix,sizeof(prefix)-1)!=0||text[size]!=0)return false;
 for(size_t i=sizeof(prefix)-1;i<size;++i){if(text[i]<'0'||text[i]>'9')return false;host=host*10+unsigned(text[i]-'0');}
 return individual(host);
}
inline bool accepted(uint64_t sender,uint64_t self,bool is_friend,const char*text,size_t capacity,uint64_t&host){
 return decode(text,capacity,host)&&sender==host&&host!=self&&individual(self)&&is_friend;
}
}
