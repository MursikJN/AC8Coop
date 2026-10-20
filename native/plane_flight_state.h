#pragma once
// Exact-build native baseline helper. Caller must hold a real owned-actor update
// barrier and verify Finish/configuration/component graph. No update release here.
#include "plane_initial_state.h"
#include <type_traits>
namespace plane_flight_state {
using plane_initial_state::Snapshot;
using plane_initial_state::OwnedCaches;
using plane_initial_state::get;
template<class T,size_t N> T value(const std::array<uint8_t,N>& a,size_t o) { T v{};std::memcpy(&v,a.data()+o,sizeof v);return v; }
struct Report {
    const char* error="not_started";
    unsigned native_calls=0, verified_scalars=0;
    bool models_seeded=false, inputs_verified=false, ready=false;
};
// Cache position is already UE world units: (mz,-mx,my)*runtimeScale.
// Apply a world displacement once; do not multiply it by runtimeScale again.
inline bool translate(Snapshot& s,int32_t x,int32_t y,int32_t z) {
    if(!s.complete||!std::isfinite(s.scale)||s.scale<=0)return false;
    const int32_t d[]={x,y,z};int32_t next[3];
    for(unsigned i=0;i<3;++i) {const int64_t n=int64_t(value<int32_t>(s.main,0x2c+i*4))+d[i];
        if(n<INT32_MIN||n>INT32_MAX)return false;next[i]=static_cast<int32_t>(n);}
    for(unsigned i=0;i<3;++i)plane_initial_state::put(s.main,0x2c+i*4,next[i]);
    return true;
}
template<class B> bool caches_match(B& b,const Snapshot& s,const OwnedCaches& o) {
    if(!plane_initial_state::verify_owned(b,s,o))return false;
    const uint8_t* blocks[]={s.main.data(),s.aux140.data(),s.aux150.data(),s.aux160.data(),s.aux170.data()};
    for(const auto& f:plane_initial_state::fields()) {
        const uintptr_t p=(f.cache==5?o.plane:o.data[f.cache])+f.offset;
        const void* expected=f.cache==5?static_cast<const void*>(&s.timestamp):blocks[f.cache]+f.offset;
        uint8_t actual[8]{};if(!b.read(p,actual,f.size)||std::memcmp(actual,expected,f.size))return false;
    }return true;
}
template<class B> bool models_owned(B& b,const Snapshot& s,const OwnedCaches& o) {
    if(!caches_match(b,s,o))return false;
    uintptr_t vt=0;if(!get(b,o.plane+0xf48,vt)||vt!=s.image+0xcc01460)return false;
    for(unsigned i=0;i<2;++i) {
        const auto m=o.plane+(i?0x3c60:0x2268);uintptr_t provider=0,bodyvt=0;uint8_t mode=0;
        if(!get(b,m+0x860,provider)||provider!=o.plane+0xf48||!get(b,m+0x8b4,mode)||mode!=i||
           !get(b,m+0xe20,bodyvt)||bodyvt!=s.image+0xbefcb80)return false;
    }return true;
}
template<class B,class T> bool eq(B& b,uintptr_t p,T expected,Report& r) {
    T actual{};if(!get(b,p,actual))return false;
    if constexpr(std::is_floating_point_v<T>) {if(!std::isfinite(actual)||!std::isfinite(expected)||
        std::fabs(actual-expected)>std::max(T(1e-6),std::fabs(expected)*T(2e-7)))return false;}
    else if(actual!=expected)return false;
    ++r.verified_scalars;return true;
}
// Reproduce only the documented scalar input filter, using this owned model's
// parameters immediately before its native input setter; no parameter cloning.
template<class B> bool expected_input(B& b,uintptr_t m,const Snapshot& s,std::array<float,6>& out) {
    float gate=0,d4=0,b0=0,limit=0,v68=0,gain=0;uint8_t dd=0;uint32_t flags=0;
    if(!get(b,m+0x89c,gate)||!get(b,m+0xd4,d4)||!get(b,m+0xb0,b0)||!get(b,m+0x9c8,limit)||
       !get(b,m+0x68,v68)||!get(b,m+0xd8,gain)||!get(b,m+0xdd,dd)||!get(b,m+0x8b0,flags))return false;
    for(float f:{gate,d4,b0,limit,v68,gain})if(!std::isfinite(f))return false;
    for(unsigned i=0;i<6;++i) {out[i]=value<float>(s.aux170,8+i*4);if(!std::isfinite(out[i]))return false;if(i<3)out[i]=-out[i];}
    if(value<uint8_t>(s.aux170,0x20)&1)out.fill(0);
    if(gate>0)out[0]=0;
    if((flags&0x1800000)||d4>0) {
        float threshold=0;if(!get(b,s.image+0xd2a921c,threshold)||!std::isfinite(threshold))return false;
        if(b0>=limit)out[3]=0;if(v68>threshold)out[3]=1;
        for(unsigned i:{0u,1u,2u,4u,5u})out[i]=plane_initial_state::rounded(out[i]*gain);
    } else if((flags&(1u<<19))&&dd){out[3]=1;out[4]=0;}
    for(unsigned i=0;i<6;++i)out[i]=std::clamp(out[i],i<3?-1.0f:0.0f,1.0f);
    return true;
}
template<class B> bool verify_model(B& b,uintptr_t m,const Snapshot& s,Report& r) {
    const double inv=static_cast<double>(plane_initial_state::rounded(1.0f/s.scale));
    const double pos[]={-double(value<int32_t>(s.main,0x30))*inv,double(value<int32_t>(s.main,0x34))*inv,double(value<int32_t>(s.main,0x2c))*inv};
    for(unsigned base:{0x8e0u,0x908u,0x930u})for(unsigned i=0;i<3;++i)if(!eq(b,m+base+i*8,pos[i],r))return false;
    float q[3][4];for(unsigned i=0;i<3;++i) {
        if(!get(b,m+(i==0?0x8d0:i==1?0x8f8:0x920),q[i]))return false;
        double norm=0;for(float v:q[i]){if(!std::isfinite(v))return false;norm+=double(v)*v;}
        if(std::fabs(norm-1)>0.002)return false;
    }
    // Setter makes first and second pose quaternions equal. Alternate pose is
    // intentionally different; equating it would reject valid native state.
    for(unsigned i=0;i<4;++i)if(std::fabs(q[0][i]-q[1][i])>1e-6f)return false;
    if(!eq(b,m+0x8b0,value<uint32_t>(s.main,0x44),r)||!eq(b,m+0x1f0,double(value<float>(s.main,0x48)),r)||
       !eq(b,m+0xb0,value<float>(s.main,0x48),r))return false;
    const unsigned axes[]={0x24,0x28,0x20};
    for(unsigned i=0;i<3;++i)if(!eq(b,m+0x1f8+i*8,double(value<float>(s.main,axes[i]))*(i?1:-1),r))return false;
    for(unsigned i=0;i<3;++i) {
        const unsigned a[]={0xc,0x10,8};
        if(!eq(b,m+0x128+i*8,double(value<float>(s.aux140,a[i]))*(i?1:-1),r)||
           !eq(b,m+0x210+i*8,double(value<float>(s.aux150,a[i]))*(i?1:-1),r)||
           !eq(b,m+0x38+i*8,double(value<float>(s.aux150,a[i]+0xc))*(i?1:-1),r))return false;
    }
    for(unsigned i=0;i<7;++i)if(!eq(b,m+0x140+i*4,value<float>(s.aux140,0x14+i*4),r))return false;
    if(!eq(b,m+0x108,value<float>(s.aux140,0x30),r)||!eq(b,m+0x118,1.0f,r)||
       !eq(b,m+0x60,value<float>(s.aux150,0x20),r)||!eq(b,m+0x64,value<float>(s.aux150,0x24),r))return false;
    const auto packed=value<uint8_t>(s.aux140,0x34);
    if(!eq(b,m+0x124,uint8_t(packed>>7),r)||!eq(b,m+0x125,uint8_t(packed&7),r)||!eq(b,m+0x126,uint8_t((packed>>3)&15),r))return false;
    const unsigned a160[]={0x24,0x28,0x20};
    for(unsigned i=0;i<3;++i)if(!eq(b,m+0x160+i*8,double(value<float>(s.aux160,a160[i]))*inv*(i?1:-1),r))return false;
    constexpr double rad=0.017453292519943295;
    for(unsigned i=0;i<3;++i)if(!eq(b,m+0x178+i*8,double(value<float>(s.aux160,0x2c+4*i))*rad*(i==2?1:-1),r))return false;
    return true;
}
// Backend native wrappers return false only before/after checked dispatch. They
// must NOT catch a native mutation fault and pretend execution can safely resume.
// reset_model:4d344f0 RCX=model; consume:74d8c00 RCX=network,RDX=model;
// input:4d32580 RCX=model,RDX=cache170+8. All execute on game thread.
template<class B> bool finalize(B& b,const Snapshot& s,const OwnedCaches& o,Report& r) {
    r={};r.error="owned_cache_or_model_identity_failed";
    if(!models_owned(b,s,o))return false;
    r.error="secondary_configuration_reset_failed";
    if(!b.reset_model(o.plane+0x3c60))return false;++r.native_calls;
    // Secondary configuration refresh writes primary provider-derived scalars.
    // Therefore finish all refresh work BEFORE consuming either baseline.
    for(uintptr_t m:{o.plane+0x2268,o.plane+0x3c60}) {
        r.error="baseline_consume_failed";if(!models_owned(b,s,o)||!b.consume(o.network,m))return false;++r.native_calls;
    }
    for(uintptr_t m:{o.plane+0x2268,o.plane+0x3c60}) {
        std::array<float,6> expected{};r.error="input_filter_prerequisites_failed";
        if(!models_owned(b,s,o)||!expected_input(b,m,s,expected))return false;
        r.error="native_input_setter_failed";if(!b.input(m,o.data[4]+8))return false;++r.native_calls;
        r.error="input_readback_failed";
        for(unsigned i=0;i<6;++i)if(!eq(b,m+i*4,expected[i],r))return false;
        if(!eq(b,m+0x18,uint8_t(value<uint8_t>(s.aux170,0x20)&31),r))return false;
    }
    r.error="model_baseline_readback_failed";
    for(uintptr_t m:{o.plane+0x2268,o.plane+0x3c60})if(!verify_model(b,m,s,r))return false;
    r.error="final_ownership_or_cache_changed";if(!models_owned(b,s,o))return false;
    r.models_seeded=true;r.inputs_verified=true;
    // ready stays false: caller still owns native configuration/component proof,
    // update permit, deadlines, error rollback and source/player preservation.
    r.error="models_seeded_readback_verified_update_barrier_retained";return true;
}
}
