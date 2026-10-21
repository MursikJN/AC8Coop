#pragma once
#include "connection_protocol.h"
#include <string>
// Asset identifiers only. Never URLs, Lua, commands, UObject addresses or callbacks.
namespace ac8cinema {
constexpr size_t packet_size=1536;
struct Descriptor {uint64_t sender=0,session=0,echo=0,sequence=0;uint32_t epoch=0,revision=0,scene=0,kind=0,duration_ms=0;std::string asset,viewer,options;};
inline bool path(const std::string&s,bool optional=false){
 if(s.empty())return optional;if(s.size()>383||(s.rfind("/Game/",0)!=0&&s.rfind("/Script/",0)!=0)||s.find("..")!=std::string::npos)return false;
 for(unsigned char c:s)if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='/'||c=='_'||c=='.'||c=='-'))return false;
 return true;
}
inline bool valid(const Descriptor&d){return d.sender&&d.session&&d.echo&&d.sequence&&d.epoch&&d.revision&&d.scene&&d.kind>=1&&d.kind<=2&&d.duration_ms>=500&&d.duration_ms<=3600000&&path(d.asset)&&path(d.viewer,d.kind==2)&&path(d.options,d.kind==1);}
inline std::array<uint8_t,packet_size> encode(const Descriptor&d){
 std::array<uint8_t,packet_size>b{};memcpy(b.data(),"AC8C",4);ac8test::put(b.data()+4,1,2);ac8test::put(b.data()+6,packet_size,2);ac8test::put(b.data()+8,ac8test::build,4);
 size_t n=16;for(auto v:{d.sender,d.session,d.echo,d.sequence}){ac8test::put(b.data()+n,v,8);n+=8;}
 n=48;for(auto v:{d.epoch,d.revision,d.scene,d.kind,d.duration_ms}){ac8test::put(b.data()+n,v,4);n+=4;}
 n=128;for(auto p:{&d.asset,&d.viewer,&d.options}){memcpy(b.data()+n,p->data(),p->size());n+=384;}return b;
}
inline bool decode(const void*p,size_t size,Descriptor&d){
 if(!p||size!=packet_size)return false;const auto*b=static_cast<const uint8_t*>(p);
 if(memcmp(b,"AC8C",4)||ac8test::get(b+4,2)!=1||ac8test::get(b+6,2)!=packet_size||ac8test::get(b+8,4)!=ac8test::build||ac8test::get(b+12,4))return false;
 for(size_t i=68;i<128;++i)if(b[i])return false;for(size_t i=128+3*384;i<size;++i)if(b[i])return false;
 d={};size_t n=16;for(auto v:{&d.sender,&d.session,&d.echo,&d.sequence}){*v=ac8test::get(b+n,8);n+=8;}
 n=48;for(auto v:{&d.epoch,&d.revision,&d.scene,&d.kind,&d.duration_ms}){*v=uint32_t(ac8test::get(b+n,4));n+=4;}
 n=128;for(auto v:{&d.asset,&d.viewer,&d.options}){size_t k=0;while(k<384&&b[n+k])++k;if(k==384)return false;v->assign(reinterpret_cast<const char*>(b+n),k);for(size_t j=k;j<384;++j)if(b[n+j])return false;n+=384;}
 return valid(d);
}
}
