#include "plane_flight_slots.h"
#include <map>
#include <stdexcept>
#include <cstdio>
using namespace plane_flight_slots;
constexpr uintptr_t source=0x100000,owned=0x200000,src_data=0x300000,dst_data=0x400000;
struct Memory {
 std::map<uintptr_t,unsigned char> bytes;unsigned writes=0,fail_write=0;
 template<class T> void put(uintptr_t p,const T& v){const auto* b=reinterpret_cast<const unsigned char*>(&v);for(size_t i=0;i<sizeof v;++i)bytes[p+i]=b[i];}
 bool read(uintptr_t p,void* out,size_t n){auto* b=static_cast<unsigned char*>(out);for(size_t i=0;i<n;++i){auto it=bytes.find(p+i);if(it==bytes.end())return false;b[i]=it->second;}return true;}
 bool write(uintptr_t p,const void* in,size_t n){++writes;if(writes==fail_write)return false;const auto* b=static_cast<const unsigned char*>(in);for(size_t i=0;i<n;++i)bytes[p+i]=b[i];return true;}
 void setup(uintptr_t plane,uintptr_t data,int32_t value){put(plane+0xfb8,data);put(plane+0xfc0,int32_t(8));put(plane+0xfc4,int32_t(8));for(unsigned i=0;i<8;++i)put(data+i*4,value);}
 Memory(){setup(source,src_data,0);setup(owned,dst_data,-1);}
 bool copy(){return copy_to_owned([&](auto p,void* o,size_t n){return read(p,o,n);},[&](auto p,const void* o,size_t n){return write(p,o,n);},source,owned);}
};
void require(bool condition){if(!condition)throw std::runtime_error("selection slot regression");}
int main(){
 unsigned tests=0;
 {Memory m;Slots s;require(read_source([&](auto p,void* o,size_t n){return m.read(p,o,n);},source,s));require(s.values.size()==8);++tests;}
 {Memory m;auto before=m.bytes;require(m.copy());require(m.writes==8);for(auto [p,v]:before)if(p<dst_data||p>=dst_data+32)require(m.bytes[p]==v);Slots d;require(read_slots([&](auto p,void* o,size_t n){return m.read(p,o,n);},owned,d));for(auto v:d.values)require(v==0);++tests;}
 {Memory m;m.put(source+0xfc0,int32_t(0));require(!m.copy()&&!m.writes);++tests;}
 {Memory m;m.put(source+0xfc4,int32_t(9));require(!m.copy()&&!m.writes);++tests;}
 {Memory m;m.put(src_data,int32_t(12));require(!m.copy()&&!m.writes);++tests;}
 {Memory m;m.put(owned+0xfb8,src_data);require(!m.copy()&&!m.writes);++tests;}
 {Memory m;m.setup(owned,src_data+8,-1);require(!m.copy()&&!m.writes);++tests;}
 {Memory m;m.put(dst_data,int32_t(0));require(!m.copy()&&!m.writes);++tests;}
 {Memory m;m.fail_write=4;require(!m.copy()&&m.writes==4);++tests;}
 {Memory m;auto read=[&](auto p,void* o,size_t n){return m.read(p,o,n);};auto write=[&](auto p,const void* o,size_t n){bool ok=m.write(p,o,n);m.put(owned+0xfc4,int32_t(9));return ok;};require(!copy_to_owned(read,write,source,owned)&&m.writes==1);++tests;}
 std::printf("%u selection slot tests passed\n",tests);return 0;
}
