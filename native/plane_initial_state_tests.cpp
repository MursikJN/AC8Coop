#include "plane_initial_state.h"
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
template<class T,size_t N>T value(const std::array<uint8_t,N>& a,size_t o){T v;std::memcpy(&v,a.data()+o,sizeof(v));return v;}
Snapshot take(Fake& f){Snapshot s;const char*e=nullptr;assert(capture(f,f.source,f.image,123,s,e));return s;}
template<class T>T binary(std::ifstream& f){T v{};f.read(reinterpret_cast<char*>(&v),sizeof(v));assert(f.good());return v;}
void replay(const char* path) {
    std::ifstream file(path,std::ios::binary);assert(file.good());
    const auto count=binary<uint32_t>(file);assert(count>0&&count<=1000);
    float max_angle_error=0;
    for(uint32_t row=0;row<count;++row) {
        Fake f;f.qpc_value=binary<uint64_t>(file);
        const auto entries=binary<uint32_t>(file);assert(entries<100);
        for(uint32_t j=0;j<entries;++j) {
            const auto p=binary<uint64_t>(file);const auto n=binary<uint32_t>(file);assert(n<=512);
            std::vector<char> data(n);file.read(data.data(),n);assert(file.good());f.seed(p,data.data(),n);
        }
        const auto s=take(f);const uint8_t* blocks[]={s.main.data(),s.aux140.data(),s.aux150.data(),s.aux160.data(),s.aux170.data()};
        const auto expected=binary<uint32_t>(file);assert(expected==45);
        for(uint32_t j=0;j<expected;++j) {
            const auto cache=binary<uint32_t>(file),offset=binary<uint32_t>(file),size=binary<uint32_t>(file);
            assert(cache<5&&size<=8);uint8_t v[8]{};file.read(reinterpret_cast<char*>(v),size);assert(file.good());
            if(cache==0&&offset>=0x38&&offset<=0x40) {
                float a,b;std::memcpy(&a,v,4);std::memcpy(&b,blocks[cache]+offset,4);
                max_angle_error=std::max(max_angle_error,std::fabs(a-b));assert(std::fabs(a-b)<=0.00002f);
            } else assert(!std::memcmp(v,blocks[cache]+offset,size));
        }
    }
    std::printf("recording replay: %u rows, all non-angle scalars byte-exact, max angle delta %.9g degrees\n",count,max_angle_error);
}
int main(int argc,char**argv){unsigned tests=0;
    {Fake f;auto s=take(f);assert(value<int32_t>(s.main,0x2c)==3000&&value<int32_t>(s.main,0x30)==-1000&&value<int32_t>(s.main,0x34)==2000);assert(value<float>(s.aux170,8)==-0.25f&&value<float>(s.aux170,0x10)==0.5f);assert(s.timestamp==value<uint64_t>(s.main,8));++tests;}
    {Fake f;auto s=take(f);auto before=f.bytes;Result r;assert(stage(f,s,f.owned,r)&&r.scalar_writes==46&&r.readback&&!r.ready&&!r.models_initialized);assert(f.written.size()==46);for(const auto& x:before){if(x.second!=f.bytes[x.first]){bool allowed=false;for(const auto&w:f.written)allowed|=x.first>=w.first&&x.first<w.first+w.second;assert(allowed);}}for(uintptr_t p=f.source;p<f.source+0x6000;++p)assert(before[p]==f.bytes[p]);++tests;}
    {Fake f;auto s=take(f);f.set(f.owned.data[0]+0x58,uint32_t{1});Result r;assert(!stage(f,s,f.owned,r)&&f.writes==0);++tests;}
    {Fake f;auto s=take(f);f.set(f.owned.network+0x20,f.source);Result r;assert(!stage(f,s,f.owned,r)&&f.writes==0);++tests;}
    {Fake f;auto s=take(f);f.set(f.owned.data[2],uintptr_t{42});Result r;assert(!stage(f,s,f.owned,r)&&f.writes==0);++tests;}
    {Fake f;auto s=take(f);f.fail_write=4;Result r;assert(!stage(f,s,f.owned,r)&&r.scalar_writes==4&&!r.ready&&!r.readback);++tests;}
    {Fake f;auto s=take(f);f.lose_guard=4;Result r;assert(!stage(f,s,f.owned,r)&&r.scalar_writes==2&&!r.ready);++tests;}
    {Fake f;auto s=take(f);f.corrupt=true;Result r;assert(!stage(f,s,f.owned,r)&&!r.readback&&!r.ready);++tests;}
    {Fake f;Snapshot s;const char*e;f.change_clock=true;assert(!capture(f,f.source,f.image,123,s,e)&&!s.complete);++tests;}
    {Fake f;Snapshot s;const char*e;f.set(f.source+0x2268+0x908,1e30);assert(!capture(f,f.source,f.image,123,s,e)&&!s.complete);++tests;}
    {Fake f;f.set(f.source+0x2268+0x8b0,uint32_t{1<<17});f.set(f.source+0x18c8,uintptr_t{0xdeadbeef});auto s=take(f);assert(value<uint8_t>(s.aux170,0x20)==0);++tests;}
    {Fake f;f.set(f.source+0x18c8,uintptr_t{0xdeadbeef});Snapshot s;const char*e;assert(!capture(f,f.source,f.image,123,s,e));f.set(f.source+0x58dc,uint8_t{1});s=take(f);assert(value<uint8_t>(s.aux170,0x20)==4&&value<float>(s.aux170,8)==0);++tests;}
    {Fake f;auto s=take(f);f.set(f.source+0xff4,-1.0f);auto newer=take(f);assert(value<float>(s.aux170,0x10)==0.5f&&value<float>(newer.aux170,0x10)==-1.0f);++tests;}
    {Fake f;auto s=take(f);f.set(f.image+0xdc4c03c,10.0f);Result r;assert(!stage(f,s,f.owned,r)&&f.writes==0);++tests;}
    std::printf("plane initial state: %u tests passed (fake memory; no native readiness proof)\n",tests);
    if(argc==2)replay(argv[1]);
}
