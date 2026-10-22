#pragma once
// Byte-addressable test fixture. No native dispatch or game data.
#include "plane_flight_state.h"
#include <cassert>
#include <cstdio>
#include <map>
#include <vector>
#include <fstream>
using namespace plane_initial_state;
struct Fake {
    std::map<uintptr_t,uint8_t> bytes;
    uintptr_t source=0x10000,image=0x140000000,clock=0x70000;
    OwnedCaches owned{0x20000,0x30000,{0x40010,0x40110,0x40210,0x40310,0x40410}};
    unsigned writes=0,guards=0,fail_write=UINT32_MAX,lose_guard=UINT32_MAX;
    bool corrupt=false,change_clock=false;
    uint64_t qpc_value=2399865359871;
    std::vector<std::pair<uintptr_t,size_t>> written;
    bool read(uintptr_t p,void* v,size_t n) {
        for(size_t i=0;i<n;++i)if(!bytes.count(p+i))return false;
        for(size_t i=0;i<n;++i)static_cast<uint8_t*>(v)[i]=bytes[p+i];return true;
    }
    bool write(uintptr_t p,const void* v,size_t n) {
        if(writes++==fail_write)return false;
        seed(p,v,n);written.push_back({p,n});if(corrupt)bytes[p]^=1;return true;
    }
    bool guard(uint64_t t,uintptr_t s,uintptr_t p,uintptr_t n) {
        return ++guards<lose_guard&&t==123&&s==source&&p==owned.plane&&n==owned.network;
    }
    bool qpc(uint64_t& q) {q=qpc_value;if(change_clock)set(clock+8,uint64_t{7});return true;}
    void seed(uintptr_t p,const void* v,size_t n){for(size_t i=0;i<n;++i)bytes[p+i]=static_cast<const uint8_t*>(v)[i];}
    template<class T>void set(uintptr_t p,T v){seed(p,&v,sizeof(v));}
    void zero(uintptr_t p,size_t n){for(size_t i=0;i<n;++i)bytes[p+i]=0;}
    Fake() {
        zero(source,0x6000);zero(owned.plane,0x6000);zero(owned.network,0x180);zero(clock,0x28);
        set(image+0xdc4c03c,100.0f);set(image+0xe525f90,clock);set(image+0xe3fad40,1e-7);
        set(clock+8,uint64_t{170167482959031});set(clock+0x18,uint64_t{639280553999970000});
        set(source+0x2268+0x868,uint8_t{1});set(source+0x2268+0x904,1.0f);
        set(source+0x2268+0x908,10.0);set(source+0x2268+0x910,20.0);set(source+0x2268+0x918,30.0);
        set(source+0x2268+0x1f8,1.0);set(source+0x6c8,1.0f);
        set(source+0xfe4,0.8f);set(source+0xfe8,0.2f);set(source+0xff4,0.5f);set(source+0xff8,-0.25f);
        set(owned.plane+0xed0,owned.network);set(owned.network+0x20,owned.plane);
        constexpr unsigned off[]={0x98,0x140,0x150,0x160,0x170};
        constexpr uintptr_t vt[]={0xbfecc70,0xbfecd10,0xbfecd50,0xbfeccd0,0xbfecd30};
        for(unsigned i=0;i<5;++i){zero(owned.data[i]-0x10,0x90);set(owned.data[i],image+vt[i]);set(owned.data[i]-8,int32_t{1});set(owned.network+off[i],owned.data[i]);set(owned.network+off[i]+8,owned.data[i]-0x10);}
    }
};
Snapshot take(Fake& f){Snapshot s;const char*e=nullptr;assert(capture(f,f.source,f.image,123,s,e));return s;}

using namespace plane_flight_state;
struct FlightFake:Fake {
    Snapshot s;
    std::vector<uintptr_t> resets,consumed,inputs;
    unsigned dispatches=0,fail_at=UINT32_MAX;
    bool wrong_pose=false,wrong_input=false;
    FlightFake() {
        s=take(*this);assert(translate(s,30000,10000,2000));
        plane_initial_state::Result r;assert(stage(*this,s,owned,r));
        set(owned.plane+0xf48,image+0xcc01460);
        set(image+0xd2a921c,0.0f);
        for(unsigned i=0;i<2;++i) {
            auto m=owned.plane+(i?0x3c60:0x2268);
            set(m+0x860,owned.plane+0xf48);set(m+0x8b4,uint8_t(i));set(m+0xe20,image+0xbefcb80);
            set(m+0xd8,1.0f);set(m+0x9c8,1000.0f);
        }
    }
    bool reset_model(uintptr_t m) {resets.push_back(m);return dispatches++!=fail_at;}
    bool consume(uintptr_t n,uintptr_t m) {
        consumed.push_back(m);assert(n==owned.network);if(dispatches++==fail_at)return false;
        const double inv=double(plane_initial_state::rounded(1.0f/s.scale));
        // Hand-derived fixture: source(10,20,30) native ->world(3000,-1000,2000),
        // translated world(33000,9000,4000) ->native(-90,40,330), with float reciprocal.
        for(unsigned p:{0x8e0u,0x908u,0x930u}){set(m+p,-9000.0*inv);set(m+p+8,4000.0*inv);set(m+p+16,33000.0*inv);}
        for(unsigned q:{0x8d0u,0x8f8u,0x920u}){zero(m+q,16);set(m+q+12,1.0f);}
        set(m+0x8b0,uint32_t{0});set(m+0x1f0,0.0);set(m+0xb0,0.0f);
        set(m+0x1f8,1.0);set(m+0x200,0.0);set(m+0x208,0.0);
        set(m+0x118,1.0f);
        if(wrong_pose)set(m+0x930,42.0);
        return true;
    }
    bool input(uintptr_t m,uintptr_t p) {
        inputs.push_back(m);assert(p==owned.data[4]+8);if(dispatches++==fail_at)return false;
        // Fixture source produces payload[-.25,0,.5,0,.8,.2] after established mapping.
        for(unsigned i=0;i<6;++i){float v=plane_flight_state::value<float>(s.aux170,8+i*4);if(i<3)v=-v;set(m+4*i,std::clamp(v,i<3?-1.0f:0.0f,1.0f));}
        set(m+0x18,uint8_t(plane_flight_state::value<uint8_t>(s.aux170,0x20)&31));
        if(wrong_input)set(m+4,0.9f);return true;
    }
};
