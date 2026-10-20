#pragma once
#include <array>
#include <cstdint>
#include <cstring>
// Exact observed source selection: eight zero IDs. Native constructor uses -1;
// consumer treats both <=0 as defaults. Never copy the owning TArray descriptor.
namespace plane_flight_slots {
struct Slots {
 uintptr_t data=0;
 std::array<unsigned char,16> descriptor{};
 std::array<int32_t,8> values{};
};
inline bool pointer(uintptr_t p) {return p>=0x10000&&p<0x800000000000ULL&&p%8==0;}
inline bool disjoint(uintptr_t a,size_t an,uintptr_t b,size_t bn) {return a+an<=b||b+bn<=a;}
template<class Read> bool read_slots(Read&& read,uintptr_t plane,Slots& out) {
 if(!pointer(plane)||!read(plane+0xfb8,out.descriptor.data(),16))return false;
 int32_t count=0,capacity=0;
 std::memcpy(&out.data,out.descriptor.data(),8);
 std::memcpy(&count,out.descriptor.data()+8,4);std::memcpy(&capacity,out.descriptor.data()+12,4);
 if(!pointer(out.data)||out.data>0x800000000000ULL-32||count!=8||capacity!=8||
    !disjoint(out.data,32,plane,0x5b00)||!read(out.data,out.values.data(),32))return false;
 std::array<unsigned char,16> after{};
 return read(plane+0xfb8,after.data(),16)&&after==out.descriptor;
}
template<class Read> bool read_source(Read&& read,uintptr_t plane,Slots& out) {
 if(!read_slots(read,plane,out))return false;
 for(auto v:out.values)if(v!=0)return false;
 return true;
}
inline bool same(const Slots& a,const Slots& b) {return a.descriptor==b.descriptor&&a.values==b.values;}
template<class Read,class Write> bool copy_to_owned(Read&& read,Write&& write,uintptr_t source,uintptr_t owned) {
 Slots src,dst;
 if(source==owned||!read_source(read,source,src)||!read_slots(read,owned,dst)||
    !disjoint(src.data,32,dst.data,32)||!disjoint(dst.data,32,source,0x5b00)||
    !disjoint(src.data,32,owned,0x5b00))return false;
 for(auto v:dst.values)if(v!=-1)return false;
 for(unsigned i=0;i<8;++i) {
  // Recheck descriptors before every bounded write. Caller supplies an identity-
  // guarded writer; a partial failure is cold cleanup, never permission to Finish.
  std::array<unsigned char,16> current{};
  if(!read(owned+0xfb8,current.data(),16)||current!=dst.descriptor||
     !read(source+0xfb8,current.data(),16)||current!=src.descriptor||
     !write(dst.data+i*4,&src.values[i],4))return false;
 }
 Slots source_after,owned_after;
 return read_source(read,source,source_after)&&same(src,source_after)&&
  read_slots(read,owned,owned_after)&&owned_after.descriptor==dst.descriptor&&owned_after.values==src.values;
}
}
