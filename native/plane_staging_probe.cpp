// Exact-build cold deferred plane staging. No Finish, Init, possession or session mutation.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <ctime>
#include <string>
#include <map>
#include <array>
#include <cstdlib>
#include <cerrno>
#include <cmath>
#include "plane_initial_state.h"
#include "plane_staging_core.h"

namespace {
constexpr uintptr_t array_rva=0xdc60cd0, spawn_rva=0x465a120, serial_rva=0x1aae560,
    destroy_rva=0x3fe0160, cdo_vtable=0xcc01cc8, player_vtable=0xcc01cc8;
constexpr unsigned ttl=120;
SRWLOCK lock=SRWLOCK_INIT;
DWORD thread_id=0;
uintptr_t image_base=0;
std::wstring directory;
HANDLE journal=INVALID_HANDLE_VALUE;
plane_stage::Ledger ledger;
unsigned write_count=0; bool cache_readback=false;
const char* cache_error="not_started";
uint64_t capture_timestamp=0; float capture_scale=0;
bool dispatcher_verified=false;
bool guarded_read(uintptr_t address,void* out,size_t bytes);
struct RawFlags { unsigned char active=0,start=0,state=0,allow=0,begin=0,finish=0; bool read_ok=false; };
RawFlags cdo_flags,pre_flags,post_flags;
bool flag_snapshot(uintptr_t actor,RawFlags& v) {
    v.read_ok=guarded_read(actor+0x3f4,&v.active,1)&&guarded_read(actor+0x32,&v.start,1)&&
      guarded_read(actor+0x33,&v.state,1)&&guarded_read(actor+0x5a,&v.allow,1)&&
      guarded_read(actor+0x5d,&v.begin,1)&&guarded_read(actor+0x5c,&v.finish,1);return v.read_ok;
}
bool ready=false;
ULONGLONG ready_tick=0;
std::string ready_stamp;

// SEH applies ONLY to bounded reads. Never catches/continues an engine mutation fault.
bool guarded_read(uintptr_t address, void* out, size_t bytes) {
    if (address<0x10000 || address>=0x800000000000ULL || !bytes || bytes>0x1000 ||
        address+bytes>=0x800000000000ULL) return false;
    __try { std::memcpy(out,reinterpret_cast<void*>(address),bytes); return true; }
    __except(GetExceptionCode()==EXCEPTION_ACCESS_VIOLATION || GetExceptionCode()==EXCEPTION_IN_PAGE_ERROR
             ? EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH) { return false; }
}
template<class T> bool read(uintptr_t p,T& value) { return guarded_read(p,&value,sizeof value); }
bool pointer(uintptr_t p) { return p>=0x10000 && p<0x800000000000ULL && !(p%8); }
bool environment(const wchar_t* key,wchar_t* out,DWORD size) {
    DWORD n=GetEnvironmentVariableW(key,out,size); return n && n<size;
}
void event(const char* what) {
    if(journal!=INVALID_HANDLE_VALUE) {
        char line[512]; const int n=std::snprintf(line,sizeof line,"%llu\t%s\t0x%llx\t%d\t%d\n",GetTickCount64(),what,
          static_cast<unsigned long long>(ledger.raw_owned),ledger.owned.index,ledger.owned.serial);
        DWORD written=0; if(n>0 && n<static_cast<int>(sizeof line)) { WriteFile(journal,line,static_cast<DWORD>(n),&written,nullptr); FlushFileBuffers(journal); }
    }
}
bool read_file(const wchar_t* name,std::string& result) {
    const std::wstring path=directory+L"\\"+name;
    HANDLE f=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(f==INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size{}; bool ok=GetFileSizeEx(f,&size) && size.QuadPart>0 && size.QuadPart<=4096;
    if(ok) {
        result.resize(static_cast<size_t>(size.QuadPart)); DWORD got=0;
        ok=ReadFile(f,&result[0],static_cast<DWORD>(result.size()),&got,nullptr) && got==result.size();
    }
    CloseHandle(f); return ok;
}
void status(const char* state,const char* reason) {
    event(reason);
    const std::wstring tmp=directory+L"\\plane-staging-status.tsv.tmp", path=directory+L"\\plane-staging-status.tsv";
    FILE* f=nullptr;
    if(_wfopen_s(&f,tmp.c_str(),L"wb") || !f) return;
    const int n=std::fprintf(f,"status\t%s\nreason\t%s\nstamp\t%s\nattempted\t%d\nowned\t0x%llx\nindex\t%d\nserial\t%d\ndestroy_requests\t%u\nretired\t%d\nnetwork\t0x%llx\nnetwork_identified\t%d\nnetwork_retired\t%d\npreinit_callbacks\t%u\nbarrier\t%d\ncache_writes\t%u\ncache_readback\t%d\ncache_error\t%s\nmodels_initialized\t0\nrelease_ready\t0\n",
        state,reason,ready_stamp.c_str(),ledger.attempted?1:0,
        static_cast<unsigned long long>(ledger.raw_owned),ledger.owned.index,ledger.owned.serial,
        ledger.destroy_requests,ledger.retired?1:0,static_cast<unsigned long long>(ledger.raw_network),ledger.network_identified?1:0,ledger.network_retired?1:0,ledger.callbacks,ledger.barrier?1:0,write_count,cache_readback?1:0,cache_error);
    int detail=std::fprintf(f,"network_creation_entered\t%d\nnetwork_outcome_unknown\t%d\nspawn_outcome_unknown\t%d\ndispatcher_verified\t%d\nsnapshot_timestamp\t%llu\nsnapshot_scale\t%.9g\nsnapshot_token\t1\n",
      ledger.network_creation_entered?1:0,ledger.network_outcome_unknown?1:0,ledger.spawn_outcome_unknown?1:0,dispatcher_verified?1:0,
      static_cast<unsigned long long>(capture_timestamp),static_cast<double>(capture_scale));
    const RawFlags* values[]={&cdo_flags,&pre_flags,&post_flags};const char* labels[]={"cdo","preinit_before","postspawn"};
    for(unsigned i=0;i<3;++i) { const auto& v=*values[i];detail+=std::fprintf(f,"%s_flags\t%d,%u,%u,%u,%u,%u,%u\n",labels[i],v.read_ok?1:0,v.active,v.start,v.state,v.allow,v.begin,v.finish); }
    const bool ok=n>0 && detail>0 && std::fflush(f)==0;
    std::fclose(f);
    if(ok) MoveFileExW(tmp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
struct Request {
    std::string stamp;
    uintptr_t world=0,controller=0,pawn=0,klass=0,cdo=0;
    uint32_t pc_offset=0,pawn_offset=0;
    double pose[6]{};
};
Request baseline;
struct Header {
    uintptr_t pointer=0;
    int32_t index=-1,serial=0;
    std::array<unsigned char,0x28> bytes{};
};
std::array<Header,5> headers;

bool parse_number(const std::string& s,uint64_t& out,int radix) {
    if(s.empty() || s.size()>20 || s[0]=='-' || s[0]=='+') return false;
    char* end=nullptr; errno=0;
    out=std::strtoull(s.c_str(),&end,radix); return !errno && end==s.c_str()+s.size();
}
bool request(Request& r) {
    std::string text; if(!read_file(L"plane-staging-request.tsv",text)) return false;
    for(unsigned char c:text) if((c<32 && c!='\t' && c!='\r' && c!='\n') || c>126) return false;
    std::map<std::string,std::string> fields;
    size_t pos=0;
    while(pos<text.size()) {
        size_t end=text.find('\n',pos); if(end==std::string::npos) end=text.size();
        std::string line=text.substr(pos,end-pos); if(!line.empty() && line.back()=='\r') line.pop_back();
        size_t tab=line.find('\t');
        if(tab==std::string::npos || line.find('\t',tab+1)!=std::string::npos ||
            !fields.emplace(line.substr(0,tab),line.substr(tab+1)).second) return false;
        pos=end+1;
    }
    const char* names[]={"format","stamp","created_unix","world","controller","pawn","plane_class","pc_pawn_offset","plane_controller_offset","location_x","location_y","location_z","rotation_pitch","rotation_yaw","rotation_roll"};
    if(fields.size()!=15) return false;
    for(auto name:names) if(!fields.count(name)) return false;
    if(fields["format"]!="ac8-plane-staging-v1") return false;
    r.stamp=fields["stamp"];
    if(r.stamp.empty() || r.stamp.size()>64) return false;
    for(char c:r.stamp) if(!((c>='0'&&c<='9')||(c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='-'||c=='_')) return false;
    uint64_t created=0; if(!parse_number(fields["created_unix"],created,10)) return false;
    const auto now=static_cast<uint64_t>(std::time(nullptr));
    if(created>now+1 || (created<=now && now-created>ttl)) return false;
    uintptr_t* targets[]={&r.world,&r.controller,&r.pawn,&r.klass};
    for(unsigned i=0;i<4;++i) { uint64_t n=0; if(!parse_number(fields[names[i+3]],n,0) || !pointer(n)) return false; *targets[i]=n; }
    uint64_t a=0,b=0;
    if(!parse_number(fields["pc_pawn_offset"],a,0) || !parse_number(fields["plane_controller_offset"],b,0) ||
        a<0x28 || a>0x2000 || a%8 || b<0x28 || b>0x2000 || b%8) return false;
    r.pc_offset=static_cast<uint32_t>(a); r.pawn_offset=static_cast<uint32_t>(b);
    for(unsigned i=0;i<6;++i) { const std::string& value=fields[names[9+i]]; char* end=nullptr; errno=0;
       r.pose[i]=std::strtod(value.c_str(),&end); if(value.empty() || errno || end!=value.c_str()+value.size() || !std::isfinite(r.pose[i]) || std::abs(r.pose[i])>1e9) return false; }
    return read(r.klass+0x110,r.cdo) && pointer(r.cdo);
}
bool item_for(int32_t index,uintptr_t& item) {
    int32_t count=0,chunks=0; uintptr_t array=0,chunk=0;
    if(index<0 || !read(image_base+array_rva+0x24,count) || count<0 || count>0x1000000 || index>=count ||
       !read(image_base+array_rva+0x2c,chunks) || chunks<=0 || chunks>0x1000 || index/65536>=chunks ||
       !read(image_base+array_rva+0x10,array) || !pointer(array) ||
       !read(array+static_cast<uintptr_t>(index/65536)*8,chunk) || !pointer(chunk)) return false;
    item=chunk+static_cast<uintptr_t>(index&65535)*0x18; return true;
}
bool capture_header(uintptr_t object,Header& h,bool require_serial) {
    uintptr_t item=0,actual=0;
    if(!pointer(object) || !guarded_read(object,h.bytes.data(),h.bytes.size())) return false;
    std::memcpy(&h.index,h.bytes.data()+0xc,4);
    if(!item_for(h.index,item) || !read(item,actual) || actual!=object || !read(item+0x10,h.serial) || h.serial<0 ||
        (require_serial && h.serial==0)) return false;
    h.pointer=object; return true;
}
bool same_header(const Header& old,bool strong) {
    Header now;
    if(!capture_header(old.pointer,now,strong) || old.index!=now.index || old.serial!=now.serial) return false;
    // ObjectFlags may change; index/class/name/Outer/vtable may not.
    return std::memcmp(old.bytes.data(),now.bytes.data(),8)==0 &&
        std::memcmp(old.bytes.data()+12,now.bytes.data()+12,0x28-12)==0;
}
bool verify_baseline(const Request& r,bool capture) {
    uintptr_t p=0,c=0,v=0,cdoclass=0,cdoptr=0;
    uint32_t flags=0; unsigned char world_type=0;
    if(!read(r.world+0x13a,world_type)||world_type!=1||!flag_snapshot(r.cdo,cdo_flags))return false;
    if(!read(r.controller+r.pc_offset,p) || p!=r.pawn || !read(r.pawn+r.pawn_offset,c) || c!=r.controller ||
       !read(r.pawn,v) || v!=image_base+player_vtable || !read(r.pawn+0x10,cdoclass) || cdoclass!=r.klass || !read(r.cdo,v) || v!=image_base+cdo_vtable ||
       !read(r.cdo+0x10,cdoclass) || cdoclass!=r.klass || !read(r.cdo+8,flags) || !(flags&0x10)) return false;
    // UClass ClassDefaultObject offset is validated from the shipped UE4SS log.
    if(!read(r.klass+0x110,cdoptr) || cdoptr!=r.cdo) return false;
    uintptr_t list[]={r.world,r.controller,r.pawn,r.klass,r.cdo};
    for(unsigned i=0;i<5;++i) {
        if(capture) { if(!capture_header(list[i],headers[i],i<3)) return false; }
        else if(list[i]!=headers[i].pointer || !same_header(headers[i],i<3)) return false;
    }
    // 3fc1ca0/3e75b40: Actor Outer is a Level; Level+c0 points to its World.
    // The player's level can differ from the World's default spawn level.
    uintptr_t level=0,outer=0,world=0; unsigned char construction=0,teardown=0,pawn_state=0;
    if(!read(r.world+0x30,level) || !pointer(level) || !read(level+0xc0,world) || world!=r.world ||
       !read(r.pawn+0x20,outer) || !pointer(outer) || !read(outer+0xc0,world) || world!=r.world ||
       !read(r.world+0x13c,construction) || (construction&2) ||
       !read(r.world+0x13d,teardown) || (teardown&0x20) ||
       !read(r.pawn+0x5d,pawn_state) || (pawn_state&1)) return false;
    for(unsigned i=0;i<3;++i) {
        uint32_t object_flags=0;
        if(!read(headers[i].pointer+8,object_flags) || (object_flags&0x40000000)) return false;
    }
    return true;
}
bool fingerprints() {
    const uintptr_t rvas[]={spawn_rva,destroy_rva,serial_rva,0x4263b80,0x7d6ed30};
    const unsigned char expected[5][16]={
        {0x40,0x55,0x53,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x48,0x8d,0xac},
        {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xec,0x20,0xf6},
        {0x40,0x57,0x48,0x83,0xec,0x20,0x3b,0x15,0x88,0x27,0x1b,0x0c,0x7d,0x1e,0x0f,0xb7},
        {0x48,0x89,0x54,0x24,0x10,0x53,0x48,0x83,0xec,0x20,0x48,0x8b,0x41,0x10,0x48,0x8b},
        {0x40,0x57,0x48,0x81,0xec,0xc0,0,0,0,0x48,0x8b,0x05,0xc0,0xde,0xeb,0x05}};
    unsigned char got[16];
    for(unsigned i=0;i<5;++i) if(!guarded_read(image_base+rvas[i],got,16) || std::memcmp(got,expected[i],16)) return false;
    return true;
}

struct Backend;
struct BridgeContext { Backend* backend=nullptr; plane_stage::Ledger* ledger=nullptr; uintptr_t expected=0; unsigned calls=0; bool self=false,matched=false; };
struct BridgeStorage { uintptr_t* table; BridgeContext* context; };
void* __fastcall bridge_address(void* p) { return static_cast<BridgeStorage*>(p)->context; }
void __fastcall bridge_invoke(void* p,uintptr_t* actor);
uintptr_t bridge_vtable[3]={0,reinterpret_cast<uintptr_t>(&bridge_address),0};
bool bridge_selfcheck() {
    BridgeContext context; context.self=true; context.expected=0x12345678;
    BridgeStorage storage{bridge_vtable,&context};
    alignas(16) uintptr_t callable[8]{};
    callable[0]=reinterpret_cast<uintptr_t>(&bridge_invoke); callable[2]=reinterpret_cast<uintptr_t>(&storage);
    using Fn=void(__fastcall*)(void*,uintptr_t);
    reinterpret_cast<Fn>(image_base+0x4263b80)(callable,context.expected);
    dispatcher_verified=context.calls==1&&context.matched;return dispatcher_verified;
}
plane_initial_state::Snapshot snapshot;
plane_initial_state::Result stage_result;
struct Backend {
    bool read(uintptr_t p,void* out,size_t bytes) { return guarded_read(p,out,bytes); }
    bool qpc(uint64_t& value) { LARGE_INTEGER now{}; if(!QueryPerformanceCounter(&now)||now.QuadPart<0)return false; value=static_cast<uint64_t>(now.QuadPart);return true; }
    void event(const char* text) { ::event(text); }
    plane_stage::Seen resolve(const plane_stage::Identity& id) {
        uintptr_t item=0,object=0; int32_t serial=0;
        if(!item_for(id.index,item)||!::read(item,object)||!::read(item+0x10,serial))return plane_stage::Seen::unknown;
        if(!object||serial!=id.serial)return plane_stage::Seen::retired;
        return object==id.pointer?plane_stage::Seen::safe:plane_stage::Seen::unknown;
    }
    bool acquire(uintptr_t object,plane_stage::Identity& identity,bool network) {
        Header h; uintptr_t vt=0,cl=0,item=0,after=0,outer=0; uint32_t flags=0;
        if(!capture_header(object,h,false)||!::read(object,vt)||vt!=image_base+(network?0xc88a868:player_vtable)||
           !::read(object+0x10,cl)||!::read(object+8,flags)||(flags&(0x10|0x20|0x40000000))||
           !::read(object+0x20,outer))return false;
        if(network) { if(outer!=ledger.raw_owned)return false; }
        else { uintptr_t level=0;if(cl!=baseline.klass||object==baseline.cdo||object==baseline.pawn||!::read(baseline.world+0x30,level)||outer!=level)return false; }
        using Fn=int32_t(__fastcall*)(uintptr_t,int32_t);
        const int32_t serial=reinterpret_cast<Fn>(image_base+serial_rva)(image_base+array_rva,h.index); int32_t stored=0;
        if(serial<=0||!item_for(h.index,item)||!::read(item,after)||after!=object||!::read(item+0x10,stored)||serial!=stored)return false;
        identity={object,h.index,serial};return true;
    }
    bool barrier_ok(uintptr_t actor) {
        unsigned char active=0,start=0,state=0,allow=0,begun=0,finish=0,world_type=0;
        return ::read(actor+0x3f4,active)&&!active&&::read(actor+0x32,start)&&!(start&4)&&
          ::read(actor+0x33,state)&&!state&&::read(actor+0x5a,allow)&&!(allow&1)&&
          ::read(actor+0x5d,begun)&&!(begun&0xc)&&::read(actor+0x5c,finish)&&!(finish&9)&&
          ::read(baseline.world+0x13a,world_type)&&world_type==1;
    }
    bool barrier(uintptr_t actor) {
        unsigned char start=0,state=0,allow=0,begun=0,finish=0,world_type=0;
        if(!flag_snapshot(actor,pre_flags))return false;
        if(resolve(ledger.owned)!=plane_stage::Seen::safe||!::read(actor+0x32,start)||!::read(actor+0x33,state)||state>1||
           !::read(actor+0x5a,allow)||!::read(actor+0x5d,begun)||(begun&0xc)||!::read(actor+0x5c,finish)||(finish&9)||
           !::read(baseline.world+0x13a,world_type)||world_type!=1)return false;
        // This is only the just-created owned actor, before engine registration. No SEH on writes.
        *reinterpret_cast<unsigned char*>(actor+0x3f4)=0;
        *reinterpret_cast<unsigned char*>(actor+0x32)=static_cast<unsigned char>(start&~4u);
        *reinterpret_cast<unsigned char*>(actor+0x33)=0;
        *reinterpret_cast<unsigned char*>(actor+0x5a)=static_cast<unsigned char>(allow&~1u);
        return barrier_ok(actor);
    }
    uintptr_t spawn(plane_stage::Ledger& receipt) {
        alignas(16) double transform[12]={0,0,0,1, baseline.pose[0],baseline.pose[1],baseline.pose[2]+30000,0, 1,1,1,0};
        alignas(16) unsigned char params[0x80]{};
        params[0x30]=1;params[0x31]=1;params[0x32]=4;uint32_t flags=8;std::memcpy(params+0x34,&flags,4);
        BridgeContext context;context.backend=this;context.ledger=&receipt;
        BridgeStorage storage{bridge_vtable,&context};
        uintptr_t invoke=reinterpret_cast<uintptr_t>(&bridge_invoke),capture=reinterpret_cast<uintptr_t>(&storage);
        std::memcpy(params+0x40,&invoke,8);std::memcpy(params+0x50,&capture,8);
        using Fn=uintptr_t(__fastcall*)(uintptr_t,uintptr_t,const void*,const void*);
        return reinterpret_cast<Fn>(image_base+spawn_rva)(baseline.world,baseline.klass,transform,params);
    }
    plane_stage::Seen inspect(const plane_stage::Identity& id) {
        const auto resolved=resolve(id);if(resolved!=plane_stage::Seen::safe)return resolved;
        unsigned char pending=0,teardown=0;uint32_t flags=0,worldflags=0;
        if(!::read(id.pointer+8,flags)||!::read(id.pointer+0x5d,pending))return plane_stage::Seen::unknown;
        if((pending&1)||(flags&0x40000000))return plane_stage::Seen::pending;
        if(!same_header(headers[0],true)||!::read(baseline.world+8,worldflags)||(worldflags&0x40000000)||
           !::read(baseline.world+0x13d,teardown)||(teardown&0x20))return plane_stage::Seen::world_lost;
        uintptr_t vt=0,cl=0,level=0,outer=0,controller=0,network=0,playerstate=0;
        if(!::read(id.pointer,vt)||vt!=image_base+player_vtable||!::read(id.pointer+0x10,cl)||cl!=baseline.klass||
           !::read(baseline.world+0x30,level)||!::read(id.pointer+0x20,outer)||outer!=level||
           !::read(id.pointer+baseline.pawn_offset,controller)||!::read(id.pointer+0x2b0,playerstate)||!::read(id.pointer+0xed0,network))return plane_stage::Seen::unknown;
        if(controller||playerstate||network!=ledger.raw_network)return plane_stage::Seen::foreign;
        return plane_stage::Seen::safe;
    }
    bool network_prerequisites(uintptr_t actor) {
        uintptr_t network=0,provider=0;
        if(!barrier_ok(actor)||!::read(actor+0xed0,network)||network||
           !::read(actor+0x2268+0x860,provider)||provider!=actor+0xf48||
           !::read(actor+0x3c60+0x860,provider)||provider!=actor+0xf48)return false;
        return flag_snapshot(actor,post_flags);
    }
    uintptr_t create_network(uintptr_t actor) {
        uintptr_t network=0;
        using Fn=void(__fastcall*)(uintptr_t);reinterpret_cast<Fn>(image_base+0x7d6ed30)(actor);
        // The verified constructor helper returns void; its owned result is installed here.
        if(!::read(actor+0xed0,network))return 0;
        return network;
    }
    bool guard(uint64_t token,uintptr_t source,uintptr_t actor,uintptr_t network) {
        return token==1&&source==baseline.pawn&&actor==ledger.raw_owned&&network==ledger.raw_network&&
          ledger.identified&&ledger.network_identified&&same_header(headers[2],true)&&
          resolve(ledger.network)==plane_stage::Seen::safe&&inspect(ledger.owned)==plane_stage::Seen::safe&&barrier_ok(actor);
    }
    bool write(uintptr_t p,const void* value,size_t bytes) {
        if(!guard(1,baseline.pawn,ledger.raw_owned,ledger.raw_network)||!bytes||bytes>8)return false;
        unsigned char before[8];if(!guarded_read(p,before,bytes))return false;
        std::memcpy(reinterpret_cast<void*>(p),value,bytes);return true;
    }
    bool stage() {
        plane_initial_state::OwnedCaches caches; caches.plane=ledger.raw_owned;caches.network=ledger.raw_network;
        const uintptr_t offsets[]={0x98,0x140,0x150,0x160,0x170};
        for(unsigned i=0;i<5;++i)if(!::read(caches.network+offsets[i],caches.data[i]))return false;
        bool ok=plane_initial_state::stage(*this,snapshot,caches,stage_result);
        write_count=stage_result.scalar_writes;cache_readback=stage_result.readback;cache_error=stage_result.error;return ok;
    }
    bool destroy(uintptr_t object) { using Fn=bool(__fastcall*)(uintptr_t,bool);return reinterpret_cast<Fn>(image_base+destroy_rva)(object,false); }
};
void __fastcall bridge_invoke(void* p,uintptr_t* actor) {
    auto* context=static_cast<BridgeContext*>(p);
    if(context->self) { ++context->calls;context->matched=actor&&*actor==context->expected;return; }
    // Dispatcher gives a pointer to a local copy; it is not the Actor pointer itself.
    context->ledger->receipt(*context->backend,actor?*actor:0);
}

bool setup(void* module_address) {
    wchar_t marker[32],out[32768],expected[32768],actual[32768];
    if(!environment(L"AC8_COOP_PLANE_STAGING",marker,32) || std::wcscmp(marker,L"25201480") ||
       !environment(L"AC8_COOP_RECON_OUTPUT",out,32768) ||
       !environment(L"AC8_COOP_PLANE_STAGING_DLL",expected,32768)) return false;
    HMODULE own=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
       reinterpret_cast<LPCWSTR>(module_address),&own)) return false;
    DWORD n=GetModuleFileNameW(own,actual,32768);
    if(!n || n>=32768 || _wcsicmp(expected,actual)) return false;
    n=GetModuleFileNameW(nullptr,actual,32768); if(!n || n>=32768) return false;
    const wchar_t* name=std::wcsrchr(actual,L'\\');
    if(!name || _wcsicmp(name+1,L"AceCombat8.exe")) return false;
    directory=out; image_base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    if(journal==INVALID_HANDLE_VALUE) {
        const std::wstring path=directory+L"\\plane-staging-lifecycle-events.tsv";
        journal=CreateFileW(path.c_str(),FILE_APPEND_DATA,FILE_SHARE_READ,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(journal==INVALID_HANDLE_VALUE) return false;
    }
    return true;
}
void dispatch(unsigned action,void* module_address) {
    if(!setup(module_address)) return;
    if(!thread_id) thread_id=GetCurrentThreadId();
    if(thread_id!=GetCurrentThreadId()) { status("error","wrong_callback_thread"); return; }
    if(!fingerprints()) { status("error","native_entry_fingerprint_mismatch"); return; }
    Backend backend;
    if(action==2) { ledger.verify(backend); status(ledger.status,ledger.reason); return; }
    if(ledger.attempted) { status("error","attempt_already_consumed_use_verify"); return; }
    Request r;
    if(!request(r)) { status("error","invalid_or_stale_request"); return; }
    if(action==0) {
        ready=false;
        if(!verify_baseline(r,true) || !bridge_selfcheck()) { status("error","baseline_identity_or_class_unverified"); return; }
        baseline=r; ready_stamp=r.stamp; ready_tick=GetTickCount64(); ready=true;
        status("ready","cold_plane_preinit_barrier_only"); return;
    }
    std::string armed;
    if(!ready || GetTickCount64()-ready_tick>ttl*1000ULL || r.stamp!=ready_stamp ||
       r.pc_offset!=baseline.pc_offset || r.pawn_offset!=baseline.pawn_offset ||
       !read_file(L"plane-staging-armed.txt",armed)) { status("error","missing_or_expired_arming"); return; }
    while(!armed.empty() && (armed.back()=='\n'||armed.back()=='\r')) armed.pop_back();
    if(armed!=ready_stamp || !verify_baseline(r,false)) { status("error","arming_or_baseline_changed"); return; }
    ready=false;
    const char* capture_error=nullptr;
    if(!plane_initial_state::capture(backend,baseline.pawn,image_base,1,snapshot,capture_error)) { status("error",capture_error?capture_error:"source_state_capture_failed"); return; }
    baseline=r;capture_timestamp=snapshot.timestamp;capture_scale=snapshot.scale;
    ledger.run(backend);
    status(ledger.status,ledger.reason);
}
int boundary(unsigned action,void* address) {
    if(!TryAcquireSRWLockExclusive(&lock)) return 0;
    // No SEH handler surrounds spawn/serial-allocation/destroy. An AV cannot become success/retry.
    try { dispatch(action,address); }
    catch(...) { if(!directory.empty()) status("error","cpp_exception_attempt_state_retained"); }
    ReleaseSRWLockExclusive(&lock); return 0;
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_plane_preflight(void*);
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_plane_preflight(void*) { return boundary(0,reinterpret_cast<void*>(&luaopen_ac8_plane_preflight)); }
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_plane_run(void*) { return boundary(1,reinterpret_cast<void*>(&luaopen_ac8_plane_preflight)); }
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_plane_verify(void*) { return boundary(2,reinterpret_cast<void*>(&luaopen_ac8_plane_preflight)); }
