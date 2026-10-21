#pragma once
#include "connection_protocol.h"
#include <algorithm>
#include <string>
#include <vector>
namespace ac8scene {
constexpr size_t header_size=80,chunk_size=16384,max_bytes=2097152;
struct Chunk{
 uint64_t sender=0,session=0,echo=0,sequence=0,generation=0,transfer=0;
 uint32_t index=0,count=0,total=0;std::string data;
};
inline bool valid(const Chunk&f){
 if(!f.sender||!f.session||!f.echo||!f.sequence||!f.generation||!f.transfer||!f.total||f.total>max_bytes)return false;
 const auto count=(f.total+chunk_size-1)/chunk_size;
 if(f.count!=count||f.index>=count)return false;
 return f.data.size()==std::min(chunk_size,size_t(f.total)-size_t(f.index)*chunk_size);
}
inline std::vector<uint8_t> encode(const Chunk&f){
 std::vector<uint8_t>b(header_size+f.data.size());memcpy(b.data(),"AC8R",4);ac8test::put(b.data()+4,1,2);ac8test::put(b.data()+6,header_size,2);
 ac8test::put(b.data()+8,ac8test::build,4);ac8test::put(b.data()+12,1,4);size_t at=16;
 for(auto v:{f.sender,f.session,f.echo,f.sequence,f.generation,f.transfer}){ac8test::put(b.data()+at,v,8);at+=8;}
 for(auto v:{uint32_t(f.data.size()),f.index,f.count,f.total}){ac8test::put(b.data()+at,v,4);at+=4;}
 memcpy(b.data()+header_size,f.data.data(),f.data.size());return b;
}
inline bool decode(const void*p,size_t n,Chunk&f){
 if(!p||n<header_size||n>header_size+chunk_size)return false;auto b=static_cast<const uint8_t*>(p);
 if(memcmp(b,"AC8R",4)||ac8test::get(b+4,2)!=1||ac8test::get(b+6,2)!=header_size||ac8test::get(b+8,4)!=ac8test::build||ac8test::get(b+12,4)!=1||ac8test::get(b+64,4)!=n-header_size)return false;
 f={};size_t at=16;for(auto v:{&f.sender,&f.session,&f.echo,&f.sequence,&f.generation,&f.transfer}){*v=ac8test::get(b+at,8);at+=8;}
 f.index=uint32_t(ac8test::get(b+68,4));f.count=uint32_t(ac8test::get(b+72,4));f.total=uint32_t(ac8test::get(b+76,4));
 f.data.assign(reinterpret_cast<const char*>(b+header_size),n-header_size);return valid(f);
}
struct Assembler{
 uint64_t generation=0,transfer=0,completed_generation=0,completed_transfer=0;uint32_t next=0,total=0,count=0;std::string pending;
 // Reliable ordered channel. No partial frame is ever delivered to the renderer.
 bool accept(const Chunk&f,std::string&out){
  out.clear();if(!valid(f)||f.generation<completed_generation||(f.generation==completed_generation&&f.transfer<=completed_transfer))return false;
  if(f.index==0){if(f.generation<generation||(f.generation==generation&&f.transfer<=transfer))return false;generation=f.generation;transfer=f.transfer;next=0;total=f.total;count=f.count;pending.clear();pending.reserve(total);}
  if(f.generation!=generation||f.transfer!=transfer||f.index!=next||f.total!=total||f.count!=count)return false;
  pending+=f.data;++next;
  if(next==count){if(pending.size()!=total)return false;out.swap(pending);completed_generation=generation;completed_transfer=transfer;}
  return true;
 }
};
}
