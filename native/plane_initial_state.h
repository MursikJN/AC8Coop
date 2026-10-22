#pragma once
// Build 25201480 cold-cache staging only. No native calls, SDK object fabrication,
// model setter, FinishSpawning, registry access, or update release lives here.
// Reader supplies checked read(address, void*, size), qpc(uint64_t&).
// Writer additionally supplies write and guard(token, source, ownedPlane, network).
// Guard must verify real callback-held barrier and fresh weak identities; an
// offline bool/test is NOT a native proof. Caller owns rollback even on failure.
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <utility>

namespace plane_initial_state {
struct Snapshot {
    uintptr_t source = 0, image = 0;
    uint64_t token = 0, timestamp = 0;
    float scale = 0;
    std::array<uint8_t, 0x80> main{};
    std::array<uint8_t, 0x38> aux140{}, aux160{};
    std::array<uint8_t, 0x28> aux150{}, aux170{};
    bool complete = false;
};
struct OwnedCaches {
    uintptr_t plane = 0, network = 0;
    std::array<uintptr_t, 5> data{};
};
struct Result {
    const char* error = "not_started";
    unsigned scalar_writes = 0;
    bool readback = false;
    // Deliberately never promoted by this cold-cache experiment.
    bool models_initialized = false, ready = false;
};
template<class T, class R> bool get(R& r, uintptr_t p, T& v) {
    return p && p <= UINTPTR_MAX - sizeof(T) && r.read(p, &v, sizeof(T));
}
template<class T, size_t N> void put(std::array<uint8_t,N>& a, size_t o, T v) {
    std::memcpy(a.data()+o, &v, sizeof(v));
}
inline float rounded(float v) { volatile float x = v; return x; }
inline float atan_native(float y, float x) {
    const float ay=std::fabs(y), ax=std::fabs(x);
    const bool swap=ay>ax;
    const float high=swap?ay:ax, low=swap?ax:ay;
    if(high==0) return 0;
    const float r=rounded(low/high), sq=rounded(r*r);
    float p=rounded(sq*0.0072128851898014545f);
    const float c[]={-0.03505967929959297f,0.08167587965726852f,
        -0.13374657928943634f,0.19856563210487366f,-0.3332499861717224f,1.0f};
    for(unsigned i=0;i<6;++i) { p=rounded(p+c[i]); if(i!=5)p=rounded(p*sq); }
    float a=rounded(r*p);
    if(swap)a=rounded(1.5707963705062866f-a);
    if(x<0)a=rounded(3.1415927410125732f-a);
    return y<0?-a:a;
}
inline std::array<float,3> angle_native(const float (&q)[4]) {
    const float x=q[0],y=q[1],z=q[2],w=q[3];
    const float xx=rounded(rounded(x+x)*x),zz=rounded(rounded(z*z)*2),yy=rounded(rounded(y*y)*2);
    const float third=atan_native(rounded(rounded(rounded(w*z)*2)+rounded(rounded(y*x)*2)),rounded(1-rounded(zz+xx)));
    const float second=atan_native(rounded(rounded(rounded(y*w)*2)+rounded(rounded(x*z)*2)),rounded(1-rounded(yy+xx)));
    const float sine=std::clamp(rounded(rounded(rounded(y*z)-rounded(w*x))*2),-1.0f,1.0f);
    return {-std::asin(sine),second,third}; // CRT last-bit equivalence unproved.
}
template<class R> bool capture(R& r, uintptr_t source, uintptr_t image, uint64_t token,
                               Snapshot& out, const char*& error) {
    out={}; error="source_read_failed";
    if(!source || !image || !token) {error="invalid_identity";return false;}
    Snapshot s; s.source=source;s.image=image;s.token=token;
    const uintptr_t m=source+0x2268;
    double d38[3],d128[3],d160[6],d1e0[3],dir[3],d210[3],pos[3];
    float f60[2],f108=0,f140[7],q[4],gain=0,in[6];
    uint8_t b124[3],selector=0,override58dc=0,b1313[3],b13d1=0,bffc=0;
    uint32_t flags=0;
    if(!get(r,m+0x38,d38)||!get(r,m+0x60,f60)||!get(r,m+0x108,f108)||
       !get(r,m+0x124,b124)||!get(r,m+0x128,d128)||!get(r,m+0x140,f140)||
       !get(r,m+0x160,d160)||!get(r,m+0x1e0,d1e0)||!get(r,m+0x1f8,dir)||
       !get(r,m+0x210,d210)||!get(r,m+0x868,selector)||!get(r,m+0x8b0,flags)||
       !get(r,m+(selector?0x908:0x930),pos)||!get(r,m+(selector?0x8f8:0x920),q)||
       !get(r,source+0x6c8,gain)||!get(r,source+0xfe4,in)||!get(r,source+0x58dc,override58dc)||
       !get(r,source+0x1313,b1313)||!get(r,source+0x13d1,b13d1)||!get(r,source+0xffc,bffc)||
       !get(r,image+0xdc4c03c,s.scale))return false;
    auto finite=[](const auto& a){for(auto v:a)if(!std::isfinite(v))return false;return true;};
    if(!finite(d38)||!finite(d128)||!finite(d160)||!finite(d1e0)||!finite(dir)||!finite(d210)||
       !finite(pos)||!finite(f60)||!finite(f140)||!finite(q)||!finite(in)||!std::isfinite(f108)||
       !std::isfinite(gain)||!std::isfinite(s.scale)||s.scale<=0) {error="nonfinite_source";return false;}
    const double p[]={pos[2]*s.scale,-pos[0]*s.scale,pos[1]*s.scale};
    for(unsigned i=0;i<3;++i) {
        if(!std::isfinite(p[i])||std::trunc(p[i])<INT32_MIN||std::trunc(p[i])>INT32_MAX){error="position_overflow";return false;}
        put(s.main,0x2c+4*i,static_cast<int32_t>(p[i]));
    }
    const double norm2=(dir[0]*dir[0]+dir[2]*dir[2])+dir[1]*dir[1];
    if(!std::isfinite(norm2)){error="direction_overflow";return false;}
    const double inv=norm2>9.99999993922529e-09?1/std::sqrt(norm2):1;
    const double direction[]={dir[2]*inv,-dir[0]*inv,dir[1]*inv};
    const auto angles=angle_native(q); constexpr double degrees=57.29577951308232;
    for(unsigned i=0;i<3;++i) {
        put(s.main,0x20+4*i,static_cast<float>(direction[i]));
        put(s.main,0x38+4*i,static_cast<float>(angles[i]*(i==2?degrees:-degrees)));
    }
    put(s.main,0x44,flags);put(s.main,0x48,static_cast<float>(d1e0[2]));
    const double a140[]={d128[2],-d128[0],d128[1]};
    const double a150[]={d210[2],-d210[0],d210[1],d38[2],-d38[0],d38[1]};
    const double a160[]={d160[2]*s.scale,-d160[0]*s.scale,d160[1]*s.scale,
        -d160[3]*degrees,-d160[4]*degrees,d160[5]*degrees};
    for(unsigned i=0;i<3;++i)put(s.aux140,8+4*i,static_cast<float>(a140[i]));
    for(unsigned i=0;i<7;++i)put(s.aux140,0x14+4*i,f140[i]);
    put(s.aux140,0x30,f108);
    put(s.aux140,0x34,static_cast<uint8_t>(((((b124[0]<<4)&255)|b124[2])<<3)|b124[1]));
    for(unsigned i=0;i<6;++i){put(s.aux150,8+4*i,static_cast<float>(a150[i]));put(s.aux160,0x20+4*i,static_cast<float>(a160[i]));}
    put(s.aux150,0x20,f60[0]);put(s.aux150,0x24,f60[1]);
    if(override58dc)put(s.aux170,0x20,uint8_t{4});
    else {
        bool bit0=false;
        if(!(flags&(1u<<17))) {
            bit0=std::fabs(rounded(in[2]-1))<0.0001f&&std::fabs(rounded(in[3]-1))<0.0001f;
            uintptr_t mode=0,actor=0,child=0; uint8_t mode_state=0,b29=0,b10=0;
            if(!get(r,source+0x18c8,mode))return false;
            if(mode) {
                if(!get(r,mode+0x108,mode_state)||!get(r,mode+0x100,actor))return false;
                bool active=mode_state==4;
                if(actor) {
                    if(!get(r,actor+0xb29,b29)||!get(r,actor+0xb40,child))return false;
                    active=active&&b29!=1;
                    if(child){if(!get(r,child+0x10,b10))return false;active=b10!=0;}
                }
                bit0=bit0||active;
            }
            bit0=bit0||b1313[2]!=0||bffc!=0;
        }
        const float values[]={std::clamp(rounded(in[5]*gain),-1.0f,1.0f),
            std::clamp(rounded(rounded(in[3]-in[2])*gain),-1.0f,1.0f),
            std::clamp(rounded(in[4]*gain),-1.0f,1.0f),std::clamp(in[0],0.0f,1.0f),
            std::clamp(in[1],0.0f,1.0f),std::clamp(b1313[0]?in[1]:rounded(rounded(in[1]+in[0])*0.5f),0.0f,1.0f)};
        for(unsigned i=0;i<6;++i)put(s.aux170,8+4*i,values[i]);
        put(s.aux170,0x20,static_cast<uint8_t>(unsigned(bit0)|(unsigned(b1313[0]!=0)<<1)|
            (unsigned(b1313[1]!=0)<<2)|(unsigned(b13d1==1)<<3)|(((flags>>9)&1)<<4)));
    }
    uintptr_t clock=0,clockAgain=0; uint64_t clockFields[4],again[4],qpc=0; double scale=0,scaleAgain=0;
    error="receiver_clock_unavailable";
    if(!get(r,image+0xe525f90,clock)||!clock||!get(r,clock+8,clockFields)||
       !get(r,image+0xe3fad40,scale)||!r.qpc(qpc)||!get(r,clock+8,again)||
       !get(r,image+0xe525f90,clockAgain)||!get(r,image+0xe3fad40,scaleAgain))return false;
    if(clock!=clockAgain||std::memcmp(clockFields,again,sizeof(again))||scale!=scaleAgain){error="clock_changed_during_capture";return false;}
    const double ticks=(static_cast<double>(qpc)*scale+16777216.0)*10000000.0;
    if(qpc>INT64_MAX||!std::isfinite(scale)||scale<=0||!std::isfinite(ticks)||ticks<0||ticks>=18446744073709551616.0){error="clock_arithmetic_invalid";return false;}
    s.timestamp=clockFields[2]-clockFields[0]+static_cast<uint64_t>(ticks)+clockFields[3];
    put(s.main,8,s.timestamp);
    // Reject finite doubles that overflowed conversion to stored float payloads.
    for(const auto& block: {std::pair<const uint8_t*,unsigned>{s.main.data()+0x20,3},
         {s.main.data()+0x38,3},{s.main.data()+0x48,1},{s.aux140.data()+8,11},
         {s.aux150.data()+8,8},{s.aux160.data()+0x20,6},{s.aux170.data()+8,6}}) {
        for(unsigned i=0;i<block.second;++i){float v;std::memcpy(&v,block.first+4*i,4);if(!std::isfinite(v)){error="float_payload_overflow";return false;}}
    }
    float scaleFinal=0;
    if(!get(r,image+0xdc4c03c,scaleFinal)||scaleFinal!=s.scale){error="runtime_scale_changed";return false;}
    s.complete=true;out=s;error="ok";return true;
}
struct Field {unsigned cache, offset, size;};
inline std::array<Field,46> fields() {
    std::array<Field,46> out{};unsigned n=0;
    for(unsigned o=0x20;o<=0x48;o+=4)out[n++]={0,o,4};
    for(unsigned o=8;o<=0x30;o+=4)out[n++]={1,o,4};out[n++]={1,0x34,1};
    for(unsigned o=8;o<=0x24;o+=4)out[n++]={2,o,4};
    for(unsigned o=0x20;o<=0x34;o+=4)out[n++]={3,o,4};
    for(unsigned o=8;o<=0x1c;o+=4)out[n++]={4,o,4};out[n++]={4,0x20,1};
    out[n++]={0,8,8};out[n++]={5,0x3c38,8};return out;
}
template<bool Self,class M> bool verify_owned_impl(M& m, const Snapshot& s, const OwnedCaches& o) {
    if(!s.complete||!o.plane||!o.network||(Self?o.plane!=s.source:o.plane==s.source)||o.network==s.source||
       !m.guard(s.token,s.source,o.plane,o.network))return false;
    uintptr_t linked=0,outer=0;
    float scale=0;
    if(!get(m,s.image+0xdc4c03c,scale)||scale!=s.scale)return false;
    if(!get(m,o.plane+0xed0,linked)||linked!=o.network||!get(m,o.network+0x20,outer)||outer!=o.plane)return false;
    constexpr unsigned offsets[]={0x98,0x140,0x150,0x160,0x170};
    constexpr uintptr_t vtables[]={0xbfecc70,0xbfecd10,0xbfecd50,0xbfeccd0,0xbfecd30};
    constexpr uintptr_t sizes[]={0x80,0x38,0x28,0x38,0x28};
    for(unsigned i=0;i<5;++i) {
        uintptr_t pair[2],vt=0;int32_t strong=0;
        if(!get(m,o.network+offsets[i],pair)||!pair[0]||pair[0]!=o.data[i]||pair[1]>UINTPTR_MAX-0x10||
           pair[0]!=pair[1]+0x10||!get(m,pair[0],vt)||vt!=s.image+vtables[i]||
           !get(m,pair[1]+8,strong)||strong<=0)return false;
        for(unsigned j=0;j<i;++j)if(o.data[i]-0x10<o.data[j]+sizes[j]&&o.data[j]-0x10<o.data[i]+sizes[i])return false;
        // Never permit a target range to overlap the source actor or target actor/network headers.
        for(uintptr_t base:{s.source,o.plane,o.network}) {
            const uintptr_t size=base==o.network?0x180:0x6000;
            if(o.data[i]<base+size&&base<o.data[i]+sizes[i])return false;
        }
    }
    // Cross-actor diagnostics require empty descriptors. The self-only route
    // preserves its own native descriptors byte-for-byte and never stages them.
    if constexpr(!Self)for(unsigned offset:{0x50u,0x60u,0x70u}) {uint64_t desc[2];if(!get(m,o.data[0]+offset,desc)||desc[0]||desc[1])return false;}
    return true;
}
template<class M> bool verify_owned(M& m,const Snapshot&s,const OwnedCaches&o){return verify_owned_impl<false>(m,s,o);}
// Explicit self-only route: cannot authorize a different source actor. The
// backend guard must pin this same object's index/serial and own update fence.
template<class M> bool verify_self_owned(M& m,const Snapshot&s,const OwnedCaches&o){return verify_owned_impl<true>(m,s,o);}
template<bool Self,class M> bool stage_impl(M& m, const Snapshot& s, const OwnedCaches& o, Result& result) {
    result={};result.error="ownership_or_barrier_unverified";
    if(!verify_owned_impl<Self>(m,s,o))return false;
    const uint8_t* blocks[]={s.main.data(),s.aux140.data(),s.aux150.data(),s.aux160.data(),s.aux170.data()};
    const auto ff=fields();
    for(const auto& f:ff) {
        if(!m.guard(s.token,s.source,o.plane,o.network)){result.error="barrier_lost_partial_commit";return false;}
        const uintptr_t target=(f.cache==5?o.plane:o.data[f.cache])+f.offset;
        const void* value=f.cache==5?static_cast<const void*>(&s.timestamp):blocks[f.cache]+f.offset;
        if(!m.write(target,value,f.size)){result.error="write_failed_partial_commit";return false;}
        ++result.scalar_writes;
    }
    if(!verify_owned_impl<Self>(m,s,o)){result.error="ownership_changed_after_commit";return false;}
    for(const auto& f:ff) {
        const uintptr_t target=(f.cache==5?o.plane:o.data[f.cache])+f.offset;
        const void* value=f.cache==5?static_cast<const void*>(&s.timestamp):blocks[f.cache]+f.offset;
        uint8_t actual[8]{};
        if(!m.read(target,actual,f.size)||std::memcmp(actual,value,f.size)){result.error="readback_mismatch";return false;}
    }
    if(!verify_owned_impl<Self>(m,s,o)){result.error="ownership_changed_after_readback";return false;}
    result.readback=true;result.error="cold_caches_verified_models_not_initialized";return true;
}
template<class M> bool stage(M&m,const Snapshot&s,const OwnedCaches&o,Result&r){return stage_impl<false>(m,s,o,r);}
template<class M> bool stage_self(M&m,const Snapshot&s,const OwnedCaches&o,Result&r){return stage_impl<true>(m,s,o,r);}
}
