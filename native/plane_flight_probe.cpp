// Exact-build bounded manual remote flight. Own objects only; no possession/session mutation.
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
#include <cstdarg>
#include "plane_initial_state.h"
#include "plane_flight_state.h"
#include "plane_flight_slots.h"
#include "plane_component_ticks.h"
#include "plane_flight_observations.h"
#include <vector>
#include "plane_flight_core.h"

namespace {
constexpr uintptr_t array_rva=0xdc60cd0, spawn_rva=0x465a120, serial_rva=0x1aae560,
    destroy_rva=0x3fe0160, cdo_vtable=0xcc01cc8, player_vtable=0xcc01cc8;
constexpr unsigned ttl=120;
SRWLOCK lock=SRWLOCK_INIT;
DWORD thread_id=0;
uintptr_t image_base=0;
std::wstring directory;
HANDLE journal=INVALID_HANDLE_VALUE;
plane_flight::Ledger ledger;
unsigned write_count=0; bool cache_readback=false;
const char* cache_error="not_started";
uint64_t capture_timestamp=0; float capture_scale=0;
const char* native_failure="not_started";
bool diagnostic_fail(const char* reason){native_failure=reason;return false;}
plane_flight_state::Report model_report;
bool dispatcher_verified=false;
bool selection_slots_copy_verified=false;
bool component_failure_seen=false;
const char* component_failure="not_started";
int32_t component_failure_index=-1;
uintptr_t component_failure_pointer=0,component_failure_setter=0,component_failure_getter=0;
plane_component_ticks::State component_failure_state;
unsigned components_verified=0;
plane_flight_observations::Schedule observation_schedule;
unsigned observation_attempts=0,observation_failures=0;
bool component_fail(const char* reason,int32_t index=-1,uintptr_t object=0,uintptr_t setter=0,uintptr_t getter=0,const plane_component_ticks::State& state={}) {
 if(!component_failure_seen){component_failure_seen=true;component_failure=reason;component_failure_index=index;component_failure_pointer=object;component_failure_setter=setter;component_failure_getter=getter;component_failure_state=state;}
 return diagnostic_fail(component_failure);
}
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
 const auto tmp=directory+L"\\plane-flight-status.tsv.tmp",path=directory+L"\\plane-flight-status.tsv";
 FILE* f=nullptr;if(_wfopen_s(&f,tmp.c_str(),L"wb")||!f)return;
 int n=std::fprintf(f,"status\t%s\nreason\t%s\nstamp\t%s\nattempted\t%d\nowned\t0x%llx\nindex\t%d\nserial\t%d\nfinish_entered\t%d\nfinished_ready\t%d\nnetwork\t0x%llx\nparts\t0x%llx\nticks\t%u\ndestroy_requests\t%u\ncache_writes\t%u\ncache_readback\t%d\ncache_error\t%s\nsnapshot_timestamp\t%llu\nsnapshot_scale\t%.9g\n",state,reason,ready_stamp.c_str(),ledger.attempted?1:0,
 static_cast<unsigned long long>(ledger.raw_owned),ledger.owned.index,ledger.owned.serial,ledger.finish_entered?1:0,ledger.finished_ready?1:0,
 static_cast<unsigned long long>(ledger.raw_network),static_cast<unsigned long long>(ledger.raw_parts),ledger.ticks,ledger.destroys,write_count,cache_readback?1:0,cache_error,
 static_cast<unsigned long long>(capture_timestamp),static_cast<double>(capture_scale));
 int extra=std::fprintf(f,"native_detail\t%s\nmodel_detail\t%s\nmodel_native_calls\t%u\nmodel_verified_scalars\t%u\nmodels_seeded\t%d\ninputs_verified\t%d\nunknown_spawn\t%d\nunknown_network\t%d\nunknown_parts\t%d\ndispatcher_verified\t%d\nmodule_revision\tr4\nselection_slots_copy_verified\t%d\nobservation_attempts\t%u\nobservation_failures\t%u\n",native_failure,model_report.error,model_report.native_calls,model_report.verified_scalars,model_report.models_seeded?1:0,model_report.inputs_verified?1:0,ledger.unknown_spawn?1:0,ledger.unknown_network?1:0,ledger.unknown_parts?1:0,dispatcher_verified?1:0,selection_slots_copy_verified?1:0,observation_attempts,observation_failures);
 int detail=std::fprintf(f,"component_detail\t%s\ncomponent_failure_index\t%d\ncomponent_failure_pointer\t0x%llx\ncomponent_setter_rva\t0x%llx\ncomponent_getter_rva\t0x%llx\ncomponent_base_tick\t%u\ncomponent_custom_d3\t%u\ncomponent_aux_registration\t0x%llx\ncomponent_aux_flags\t%u\ncomponents_verified\t%u\n",component_failure,component_failure_index,static_cast<unsigned long long>(component_failure_pointer),static_cast<unsigned long long>(component_failure_setter),static_cast<unsigned long long>(component_failure_getter),unsigned(component_failure_state.base_tick),unsigned(component_failure_state.custom_enabled),static_cast<unsigned long long>(component_failure_state.aux_registration),unsigned(component_failure_state.aux_flags),components_verified);
 bool ok=n>0&&extra>0&&detail>0&&std::fflush(f)==0;std::fclose(f);if(ok)MoveFileExW(tmp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
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
    std::string text; if(!read_file(L"plane-flight-request.tsv",text)) return false;
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
    if(fields["format"]!="ac8-plane-flight-v1") return false;
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
    if(!read(r.world+0x13a,world_type)||world_type!=1)return diagnostic_fail("baseline_world_type_unverified");
    if(!flag_snapshot(r.cdo,cdo_flags))return diagnostic_fail("baseline_cdo_flags_unreadable");
    if(!read(r.controller+r.pc_offset,p)||p!=r.pawn)return diagnostic_fail("baseline_controller_pawn_mismatch");
    if(!read(r.pawn+r.pawn_offset,c)||c!=r.controller)return diagnostic_fail("baseline_pawn_controller_mismatch");
    if(!read(r.pawn,v)||v!=image_base+player_vtable)return diagnostic_fail("baseline_pawn_vtable_mismatch");
    if(!read(r.pawn+0x10,cdoclass)||cdoclass!=r.klass)return diagnostic_fail("baseline_pawn_class_mismatch");
    if(!read(r.cdo,v)||v!=image_base+cdo_vtable)return diagnostic_fail("baseline_cdo_vtable_mismatch");
    if(!read(r.cdo+0x10,cdoclass)||cdoclass!=r.klass)return diagnostic_fail("baseline_cdo_class_mismatch");
    if(!read(r.cdo+8,flags)||!(flags&0x10))return diagnostic_fail("baseline_cdo_flag_missing");
    // UClass ClassDefaultObject offset is validated from the shipped UE4SS log.
    if(!read(r.klass+0x110,cdoptr) || cdoptr!=r.cdo)return diagnostic_fail("baseline_class_cdo_mismatch");
    uintptr_t list[]={r.world,r.controller,r.pawn,r.klass,r.cdo};
    const char* header_errors[]={"baseline_world_identity_unverified","baseline_controller_identity_unverified","baseline_pawn_identity_unverified","baseline_class_identity_unverified","baseline_cdo_identity_unverified"};
    for(unsigned i=0;i<5;++i) {
        if(capture) { if(!capture_header(list[i],headers[i],i<3))return diagnostic_fail(header_errors[i]); }
        else if(list[i]!=headers[i].pointer || !same_header(headers[i],i<3))return diagnostic_fail(header_errors[i]);
    }
    // 3fc1ca0/3e75b40: Actor Outer is a Level; Level+c0 points to its World.
    // The player's level can differ from the World's default spawn level.
    uintptr_t level=0,outer=0,world=0; unsigned char construction=0,teardown=0,pawn_state=0;
    if(!read(r.world+0x30,level)||!pointer(level)||!read(level+0xc0,world)||world!=r.world)return diagnostic_fail("baseline_world_level_mismatch");
    if(!read(r.pawn+0x20,outer)||!pointer(outer)||!read(outer+0xc0,world)||world!=r.world)return diagnostic_fail("baseline_pawn_world_mismatch");
    if(!read(r.world+0x13c,construction)||(construction&2))return diagnostic_fail("baseline_world_construction_active");
    if(!read(r.world+0x13d,teardown)||(teardown&0x20))return diagnostic_fail("baseline_world_teardown_active");
    if(!read(r.pawn+0x5d,pawn_state)||(pawn_state&1))return diagnostic_fail("baseline_pawn_destroy_pending");
    const char* flag_errors[]={"baseline_world_pending_flags","baseline_controller_pending_flags","baseline_pawn_pending_flags"};
    for(unsigned i=0;i<3;++i) {
        uint32_t object_flags=0;
        if(!read(headers[i].pointer+8,object_flags) || (object_flags&0x40000000))return diagnostic_fail(flag_errors[i]);
    }
    return true;
}
bool fingerprints(){
 const uintptr_t rvas[]={0x465a120,0x3fe0160,0x1aae560,0x4263b80,0x7d6ed30,0x7d4ad20,0x3fdc360,0x3fc34c0,0x41df200,0x4d344f0,0x74d8c00,0x4d32580,0x4d318a0,0x3fdebc0,0x7d6f0c0,0x42dfa90,0x7d2c180,0x7d2c120,0x41df3e0};
 const unsigned char expected[][16]={
{0x40,0x55,0x53,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x48,0x8d,0xac},
{0x48,0x89,0x5c,0x24,0x8,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xec,0x20,0xf6},
{0x40,0x57,0x48,0x83,0xec,0x20,0x3b,0x15,0x88,0x27,0x1b,0xc,0x7d,0x1e,0xf,0xb7},
{0x48,0x89,0x54,0x24,0x10,0x53,0x48,0x83,0xec,0x20,0x48,0x8b,0x41,0x10,0x48,0x8b},
{0x40,0x57,0x48,0x81,0xec,0xc0,0x0,0x0,0x0,0x48,0x8b,0x5,0xc0,0xde,0xeb,0x5},
{0x4c,0x8b,0xdc,0x55,0x41,0x55,0x41,0x56,0x49,0x8d,0x6b,0xb8,0x48,0x81,0xec,0x30},
{0x40,0x55,0x56,0x57,0x41,0x54,0x41,0x57,0x48,0x8d,0xac,0x24,0x90,0xfc,0xff,0xff},
{0xf6,0x41,0x32,0x2,0x74,0x26,0x48,0x8b,0xc1,0xf,0x1f,0x80,0x0,0x0,0x0,0x0},
{0xf6,0x41,0x3a,0x2,0x74,0x26,0x48,0x8b,0xc1,0xf,0x1f,0x80,0x0,0x0,0x0,0x0},
{0x48,0x89,0x5c,0x24,0x8,0x57,0x48,0x83,0xec,0x20,0x48,0x8d,0xb9,0xc0,0x9,0x0},
{0x48,0x8b,0xc4,0x48,0x89,0x58,0x8,0x48,0x89,0x70,0x10,0x48,0x89,0x78,0x18,0x55},
{0x48,0x83,0xec,0x38,0xf6,0x42,0x18,0x1,0xf,0x57,0xc9,0xf3,0xf,0x10,0x5,0xfd},
{0x40,0x53,0x48,0x81,0xec,0x80,0x0,0x0,0x0,0xf3,0xf,0x10,0xd,0x77,0x79,0x57},
{0x48,0x81,0xec,0x78,0x1,0x0,0x0,0x48,0x8b,0x89,0xa0,0x1,0x0,0x0,0x48,0x85},
{0x40,0x55,0x53,0x48,0x8d,0xac,0x24,0xd8,0xfe,0xff,0xff,0x48,0x81,0xec,0x28,0x2},
{0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0xf6,0x41,0x3a,0x02,0x0f,0xb6},
{0x88,0x91,0xd3,0x00,0x00,0x00,0xc3,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc},
{0x48,0x83,0xec,0x28,0x48,0x83,0xb9,0xc0,0x00,0x00,0x00,0x00,0x74,0x3c,0x48,0x8b},
{0x80,0x79,0x3b,0x00,0x0f,0x95,0xc0,0xc3,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc}};
 unsigned char got[16];for(unsigned i=0;i<sizeof(rvas)/sizeof(rvas[0]);++i)if(!guarded_read(image_base+rvas[i],got,16)||std::memcmp(got,expected[i],16))return false;return true;
}
struct Backend;
struct BridgeContext { Backend* backend=nullptr; plane_flight::Ledger* ledger=nullptr; uintptr_t expected=0; unsigned calls=0; bool self=false,matched=false; };
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
    dispatcher_verified=context.calls==1&&context.matched;
    if(context.calls!=1)return diagnostic_fail("dispatcher_selfcheck_invocation_count");
    if(!context.matched)return diagnostic_fail("dispatcher_selfcheck_context_mismatch");
    return true;
}
plane_initial_state::Snapshot snapshot;
plane_initial_state::Result stage_result;
struct SourceConfig {
 Header parts{},activator{},target{},indicator{},weapon{},nested{},extra{},metadata{},gameinstance{},strix{};
 uintptr_t gi=0,manager=0;
 std::vector<int32_t> part_ids;
 std::array<unsigned char,0x48> scalars{};
 plane_flight_slots::Slots selection_ids;
 int32_t row=0;
};
SourceConfig source_config;
constexpr uint64_t owned_net_id=0x434f4f5000000001ULL;
constexpr int32_t dx=30000,dy=10000,dz=2000;
uint64_t last_motion_ms=0;
std::vector<Header> owned_components;
bool integer_array(uintptr_t address,unsigned cap,std::vector<int32_t>& values) {
 uintptr_t data=0;int32_t count=0,capacity=0;
 if(!::read(address,data)||!::read(address+8,count)||!::read(address+12,capacity)||count<0||count>static_cast<int32_t>(cap)||capacity<count||capacity>4096)return false;
 values.resize(count);return !count||(pointer(data)&&guarded_read(data,values.data(),count*4));
}
bool registry_absent() {
 const auto& c=source_config;uintptr_t manager=0;
 if(!same_header(c.gameinstance,true))return diagnostic_fail("registry_gameinstance_identity_changed");
 if(!same_header(c.strix,false))return diagnostic_fail("registry_strix_identity_changed");
 if(!::read(c.gi+0x910,manager)||manager!=c.manager)return diagnostic_fail("registry_gameinstance_strix_mismatch");
 unsigned char active=0;if(!::read(manager+0x1fa,active))return diagnostic_fail("registry_room_active_flag_unreadable");
 if(active)return diagnostic_fail("registry_room_is_active");
 unsigned char raw[0x50];if(!guarded_read(manager+0x2e0,raw,sizeof raw))return diagnostic_fail("registry_map_header_unreadable");
 uintptr_t data=0,external=0;int32_t count=0,free=0,buckets=0;
 std::memcpy(&data,raw,8);std::memcpy(&count,raw+8,4);std::memcpy(&free,raw+0x34,4);std::memcpy(&external,raw+0x40,8);std::memcpy(&buckets,raw+0x48,4);
 if(count<0||count>1000000||free<0||free>count)return diagnostic_fail("registry_sparse_count_invalid");
 if(count==free)return true;
 if(buckets<=0||buckets>1048576||(buckets&(buckets-1))||(!external&&buckets>2)||!pointer(data))return diagnostic_fail("registry_bucket_layout_invalid");
 uintptr_t table=external?external:manager+0x2e0+0x38;if(!pointer(table))return diagnostic_fail("registry_bucket_pointer_invalid");
 uint32_t hash=static_cast<uint32_t>(owned_net_id)+23u*static_cast<uint32_t>(owned_net_id>>32);
 int32_t index=0;if(!::read(table+(hash&static_cast<uint32_t>(buckets-1))*4,index))return diagnostic_fail("registry_bucket_unreadable");
 unsigned hops=0;while(index!=-1){if(index<0||index>=count||++hops>128)return diagnostic_fail("registry_chain_bounds_invalid");
  uint64_t key=0;if(!::read(data+static_cast<uintptr_t>(index)*24,key))return diagnostic_fail("registry_key_unreadable");
  if(key==owned_net_id)return diagnostic_fail("registry_owned_id_collision");
  if(!::read(data+static_cast<uintptr_t>(index)*24+16,index))return diagnostic_fail("registry_next_index_unreadable");
 }
 unsigned char after[0x50];
 if(!guarded_read(manager+0x2e0,after,sizeof after)||std::memcmp(raw,after,sizeof raw))return diagnostic_fail("registry_header_changed_during_read");
 return true;
}
bool source_configuration(bool capture) {
 auto& c=source_config;uintptr_t p=baseline.pawn,gi=0,parts=0,activator=0,target=0,indicator=0,weapon=0,nested=0,extra=0,metadata=0,manager=0;
 if(!::read(baseline.world+0x1d8,gi)||!pointer(gi))return diagnostic_fail("config_gameinstance_pointer_unverified");
 if(!::read(gi+0x878,metadata)||!pointer(metadata))return diagnostic_fail("config_metadata_pointer_unverified");
 if(!::read(gi+0x910,manager)||!pointer(manager))return diagnostic_fail("config_strix_pointer_unverified");
 if(!::read(p+0x1328,parts))return diagnostic_fail("config_parts_pointer_unreadable");
 if(!::read(p+0x16a8,activator)||!pointer(activator))return diagnostic_fail("config_activator_pointer_unverified");
 if(!::read(p+0x1ae8,target))return diagnostic_fail("config_target_pointer_unreadable");
 if(!::read(p+0x18d8,indicator))return diagnostic_fail("config_indicator_pointer_unreadable");
 if(!::read(activator+0x2e0,weapon)||!pointer(weapon))return diagnostic_fail("config_weapon_pointer_unverified");
 if(!::read(weapon+0xa8,nested))return diagnostic_fail("config_nested_weapon_pointer_unreadable");
 if(!::read(activator+0x2e8,extra))return diagnostic_fail("config_activator_extra_pointer_unreadable");
 Header* hs[]={&c.parts,&c.activator,&c.target,&c.indicator,&c.weapon,&c.nested,&c.extra,&c.metadata,&c.gameinstance,&c.strix};
 uintptr_t ps[]={parts,activator,target,indicator,weapon,nested,extra,metadata,gi,manager};
 const char* identity_errors[]={"config_parts_identity_unverified","config_activator_identity_unverified","config_target_identity_unverified","config_indicator_identity_unverified","config_weapon_identity_unverified","config_nested_weapon_identity_unverified","config_activator_extra_identity_unverified","config_metadata_identity_unverified","config_gameinstance_identity_unverified","config_strix_identity_unverified"};
 for(unsigned i=0;i<10;++i){if(capture){if(!capture_header(ps[i],*hs[i],i==8))return diagnostic_fail(identity_errors[i]);}else if(ps[i]!=hs[i]->pointer||!same_header(*hs[i],i==8))return diagnostic_fail(identity_errors[i]);}
 const char* outer_errors[]={"config_parts_outer_mismatch","config_activator_outer_mismatch","config_target_outer_mismatch","config_indicator_outer_mismatch","config_weapon_outer_mismatch","config_nested_weapon_outer_mismatch","config_activator_extra_outer_mismatch"};
 for(unsigned i=0;i<7;++i){uintptr_t outer=0;if(!::read(ps[i]+0x20,outer)||outer!=(i==6?activator:p))return diagnostic_fail(outer_errors[i]);}
 if(capture){c.gi=gi;c.manager=manager;}else if(c.gi!=gi||c.manager!=manager)return diagnostic_fail("config_gameinstance_or_strix_changed");
 std::vector<int32_t> ids,other;
 if(!integer_array(parts+0x30,16,ids))return diagnostic_fail("config_parts_primary_array_invalid");
 if(!integer_array(parts+0x40,16,other)||!other.empty())return diagnostic_fail("config_parts_secondary_array_not_empty_or_invalid");
 plane_flight_slots::Slots selection_ids;
 auto reader=[](uintptr_t address,void* data,size_t size){return guarded_read(address,data,size);};
 if(!plane_flight_slots::read_source(reader,p,selection_ids))return diagnostic_fail("config_selection_ids_not_eight_zeros_or_invalid");
 for(auto id:ids)if(id<0)return diagnostic_fail("config_part_id_negative");
 int32_t effects=0;if(!::read(parts+0x1a7f0,effects)||effects)return diagnostic_fail("config_parts_effects_not_empty_or_unreadable");
 std::array<unsigned char,0x48> scalars;int32_t row=0;
 if(!guarded_read(p+0xf98,scalars.data(),scalars.size()))return diagnostic_fail("config_loadout_scalars_unreadable");
 if(!::read(p+0x3ab8,row)||row!=0)return diagnostic_fail("config_flight_row_not_zero_or_unreadable");
 if(capture){c.part_ids=ids;c.scalars=scalars;c.row=row;c.selection_ids=selection_ids;}
 else if(ids!=c.part_ids||scalars!=c.scalars||row!=c.row||!plane_flight_slots::same(selection_ids,c.selection_ids))return diagnostic_fail("config_selected_loadout_changed");
 return registry_absent();
}
namespace observation=plane_flight_observations;
struct ObservationReader {
 bool read(uintptr_t p,void* out,size_t bytes){return guarded_read(p,out,bytes);}
 bool identify(uintptr_t p,observation::Identity& out){
  Header h;if(!capture_header(p,h,false))return false;
  out={};out.pointer=p;out.index=h.index;out.serial=h.serial;
  std::memcpy(&out.vtable,h.bytes.data(),8);std::memcpy(&out.flags,h.bytes.data()+8,4);
  std::memcpy(&out.klass,h.bytes.data()+0x10,8);std::memcpy(&out.name,h.bytes.data()+0x18,8);std::memcpy(&out.outer,h.bytes.data()+0x20,8);return true;
 }
 bool unchanged(const observation::Identity& old){observation::Identity now;return identify(old.pointer,now)&&observation::same_identity(old,now);}
 bool scene(uintptr_t object){
  uintptr_t root=0,klass=0,chain=0,entry=0;int32_t index=0,count=0;
  return ::read(image_base+0xe4a8958,root)&&pointer(root)&&::read(root+0x38,index)&&index>=0&&index<1024&&
   ::read(object+0x10,klass)&&pointer(klass)&&::read(klass+0x38,count)&&count>=index&&count<1024&&
   ::read(klass+0x30,chain)&&pointer(chain)&&::read(chain+static_cast<uintptr_t>(index)*8,entry)&&entry==root+0x30;
 }
};
struct ObservationJson {
 std::string text;bool ok=true;
 void add(const char* format,...){
  if(!ok)return;char buffer[2048];va_list args;va_start(args,format);int n=std::vsnprintf(buffer,sizeof buffer,format,args);va_end(args);
  if(n<0||n>=static_cast<int>(sizeof buffer)||text.size()+static_cast<size_t>(n)>2*1024*1024){ok=false;return;}text.append(buffer,static_cast<size_t>(n));
 }
 template<size_t N> void hex(const std::array<unsigned char,N>& bytes,bool valid){
  if(!valid){add("null");return;}add("\"");for(unsigned char b:bytes)add("%02x",unsigned(b));add("\"");
 }
 void vec(const observation::Vec& value,bool valid){if(!valid||!observation::finite(value)){add("null");return;}add("[%.17g,%.17g,%.17g]",value[0],value[1],value[2]);}
};
const char* boolean(bool value){return value?"true":"false";}
void observation_identity(ObservationJson& j,const observation::Identity& x){
 j.add("{\"pointer\":\"0x%llx\",\"index\":%d,\"serial\":%d,\"class\":\"0x%llx\",\"vtable\":\"0x%llx\",\"outer\":\"0x%llx\",\"flags\":%u}",
  static_cast<unsigned long long>(x.pointer),x.index,x.serial,static_cast<unsigned long long>(x.klass),static_cast<unsigned long long>(x.vtable),static_cast<unsigned long long>(x.outer),x.flags);
}
void observation_scene(ObservationJson& j,const observation::Scene& x){
 j.add("{\"identity_valid\":%s,\"identity\":",boolean(x.identity_valid));observation_identity(j,x.identity);
 j.add(",\"scene_verified\":%s,\"owner_matches\":%s,\"owner\":\"0x%llx\",\"transform_valid\":%s,\"world_xyz\":",boolean(x.scene_verified),boolean(x.owner_matches),static_cast<unsigned long long>(x.owner),boolean(x.transform_valid));
 j.vec(x.world,x.transform_valid);j.add(",\"raw_transform_valid\":%s,\"raw_200_260_hex\":",boolean(x.raw_transform_valid));j.hex(x.raw_transform,x.raw_transform_valid);
 j.add(",\"flags_valid\":%s,\"raw_188_191_hex\":",boolean(x.flags_valid));j.hex(x.raw_flags,x.flags_valid);j.add("}");
}
void observation_reference(ObservationJson& j,const observation::Reference& x){j.add("{\"valid\":%s,\"identity\":",boolean(x.valid));observation_identity(j,x.identity);j.add("}");}
void observation_actor(ObservationJson& j,const observation::Actor& x){
 j.add("{\"identity_valid\":%s,\"identity\":",boolean(x.identity_valid));observation_identity(j,x.identity);
 j.add(",\"flags_valid\":%s,\"raw58\":",boolean(x.flags_valid));if(x.flags_valid)j.add("%u",unsigned(x.raw58));else j.add("null");
 j.add(",\"hidden_bit80\":");if(x.flags_valid)j.add("%s",boolean((x.raw58&0x80)!=0));else j.add("null");
 j.add(",\"active3f4\":");if(x.flags_valid)j.add("%u",unsigned(x.active3f4));else j.add("null");
 j.add(",\"root_pointer\":\"0x%llx\",\"root\":",static_cast<unsigned long long>(x.root_pointer));
 observation_scene(j,x.root);j.add(",\"geometry_15a0\":");observation_reference(j,x.geometry15a0);j.add(",\"geometry_1af8\":");observation_reference(j,x.geometry1af8);j.add("}");
}
void observation_delta(ObservationJson& j,const observation::Delta& d){
 j.add("{\"valid\":%s,\"xyz\":",boolean(d.valid));j.vec(d.xyz,d.valid);j.add(",\"distance\":");if(d.valid&&std::isfinite(d.distance))j.add("%.17g",d.distance);else j.add("null");j.add("}");
}
bool append_observation(const wchar_t* filename,ObservationJson& j){
 if(!j.ok)return false;j.add("\n");if(!j.ok)return false;
 const std::wstring path=directory+L"\\"+filename;
 HANDLE f=CreateFileW(path.c_str(),FILE_APPEND_DATA,FILE_SHARE_READ,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(f==INVALID_HANDLE_VALUE)return false;DWORD written=0;bool ok=WriteFile(f,j.text.data(),static_cast<DWORD>(j.text.size()),&written,nullptr)&&written==j.text.size();CloseHandle(f);return ok;
}
struct ObservationComponent {int32_t index=-1;observation::Scene scene{};bool tick_valid=false;uint8_t tick3a=0,tick3b=0;};
struct ObservationComponents {bool valid=false;int32_t slots=0;unsigned skipped_scene_gate=0;std::vector<ObservationComponent> entries;};
bool capture_observation_components(ObservationReader& r,uintptr_t actor,ObservationComponents& result){
 observation::Identity identity;if(!r.identify(actor,identity))return false;
 const uintptr_t set=actor+0x218;std::array<unsigned char,0x38> raw{},after{};
 if(!r.read(set,raw.data(),raw.size()))return false;uintptr_t data=0,external=0;int32_t n=0,max=0,bits=0,maxbits=0,free=0;
 std::memcpy(&data,raw.data(),8);std::memcpy(&n,raw.data()+8,4);std::memcpy(&max,raw.data()+12,4);std::memcpy(&external,raw.data()+0x20,8);
 std::memcpy(&bits,raw.data()+0x28,4);std::memcpy(&maxbits,raw.data()+0x2c,4);std::memcpy(&free,raw.data()+0x34,4);
 if(n<0||n>512||bits!=n||max<n||max>4096||maxbits<bits||maxbits>4096||free<0||free>n||(!external&&bits>128)||!pointer(data))return false;
 result.slots=n;const uintptr_t bitmap=external?external:set+0x10;if(!pointer(bitmap))return false;
 unsigned allocated=0;bool readable=true;result.entries.reserve(static_cast<size_t>(n));
 for(int32_t i=0;i<bits;++i){uint32_t word=0;if(!::read(bitmap+static_cast<uintptr_t>(i/32)*4,word))return false;if(!(word&(1u<<(i%32))))continue;++allocated;
  uintptr_t object=0;if(!::read(data+static_cast<uintptr_t>(i)*16,object)){readable=false;continue;}
  if(!r.scene(object)){++result.skipped_scene_gate;continue;}
  ObservationComponent item;item.index=i;observation::capture_scene(r,object,actor,item.scene);
  if(!item.scene.identity_valid||!item.scene.owner_matches){readable=false;continue;}
  item.tick_valid=::read(object+0x3a,item.tick3a)&&::read(object+0x3b,item.tick3b)&&r.unchanged(item.scene.identity);
  result.entries.push_back(item);
 }
 result.valid=readable&&allocated==static_cast<unsigned>(n-free)&&r.read(set,after.data(),after.size())&&raw==after&&r.unchanged(identity);return result.valid;
}
bool emit_observation_components(observation::Stage stage,uint64_t elapsed,bool eligible){
 ObservationReader r;ObservationComponents c;if(eligible)capture_observation_components(r,ledger.raw_owned,c);
 ObservationJson j;j.add("{\"schema\":\"ac8-flight-components-r4\",\"stage\":\"%s\",\"elapsed_ms\":%llu,\"units\":\"UE_centimeters\",\"set_valid\":%s,\"allocation_slots\":%d,\"scene_count\":%u,\"skipped_non_scene_or_unverified\":%u,\"registration_status\":\"not_decoded\",\"components\":[",observation::name(stage),static_cast<unsigned long long>(elapsed),boolean(c.valid),c.slots,static_cast<unsigned>(c.entries.size()),c.skipped_scene_gate);
 bool first=true;for(const auto& x:c.entries){if(!first)j.add(",");first=false;j.add("{\"index\":%d,\"tick_valid\":%s,\"raw3a\":%u,\"raw3b\":%u,\"scene\":",x.index,boolean(x.tick_valid),unsigned(x.tick3a),unsigned(x.tick3b));observation_scene(j,x.scene);j.add("}");}j.add("]}");
 bool written=append_observation(L"plane-flight-components-r4.jsonl",j);return written&&c.valid;
}
struct ObservationFrame {observation::Actor source_before{},owned_before{},source_after{},owned_after{};observation::Vec requested{};bool requested_valid=false;};
ObservationFrame pending_observation;
observation::Stage pending_observation_stage=observation::Stage::none;
uint64_t pending_observation_elapsed=0;
bool pending_observation_moved=false;
bool emit_observation_frame(observation::Stage stage,uint64_t elapsed,const ObservationFrame& f,bool attempted,bool moved){
 auto m=observation::metrics(f.owned_before,f.owned_after,f.source_after,f.requested,f.requested_valid);
 ObservationJson j;j.add("{\"schema\":\"ac8-flight-observation-r4\",\"contract\":\"flight-r4-observation-contract.json\",\"stage\":\"%s\",\"elapsed_ms\":%llu,\"units\":\"UE_centimeters\",\"layout\":{\"root_raw_offset\":\"0x200\",\"root_raw_size\":96,\"xyz_offset\":\"0x220\",\"xyz_type\":\"double[3]\",\"scene_flags_offset\":\"0x188\",\"scene_flags_size\":9},\"pose_attempted\":%s,\"move_returned\":%s,\"requested_origin\":\"%s\",\"requested_world\":",observation::name(stage),static_cast<unsigned long long>(elapsed),boolean(attempted),boolean(moved),attempted?"pose_argument":"model_at_cleanup");j.vec(f.requested,f.requested_valid);
 j.add(",\"source_before\":");observation_actor(j,f.source_before);j.add(",\"owned_before\":");observation_actor(j,f.owned_before);
 j.add(",\"source_after\":");observation_actor(j,f.source_after);j.add(",\"owned_after\":");observation_actor(j,f.owned_after);
 j.add(",\"metrics\":{\"actual_step\":");observation_delta(j,m.actual_step);j.add(",\"request_error\":");observation_delta(j,m.request_error);j.add(",\"source_delta\":");observation_delta(j,m.source_delta);j.add("}}");
 bool written=append_observation(L"plane-flight-observations-r4.jsonl",j);return written&&f.owned_after.identity_valid&&f.owned_after.root.transform_valid;
}
struct Backend {
 bool read(uintptr_t p,void* out,size_t bytes){return guarded_read(p,out,bytes);}
 bool qpc(uint64_t& v){LARGE_INTEGER n{};if(!QueryPerformanceCounter(&n)||n.QuadPart<0)return false;v=static_cast<uint64_t>(n.QuadPart);return true;}
 void event(const char* text){::event(text);}
 uint64_t now(){return GetTickCount64();}
 void capture_observation_phase(ObservationFrame& frame,bool after) noexcept {
  observation::best_effort([&](){
   ObservationReader r;auto& source=after?frame.source_after:frame.source_before;auto& owned=after?frame.owned_after:frame.owned_before;
   bool source_ok=same_header(headers[2],true)&&observation::capture_actor(r,baseline.pawn,source);
   bool owned_ok=ledger.identified&&resolve(ledger.owned)==plane_flight::Seen::safe&&observation::capture_actor(r,ledger.raw_owned,owned);
   return source_ok&&owned_ok;
  },observation_failures);
 }
 void flush_observation() noexcept {
  if(pending_observation_stage==observation::Stage::none)return;
  const auto stage=pending_observation_stage;pending_observation_stage=observation::Stage::none;
  capture_observation_phase(pending_observation,true);
  observation::best_effort([&](){return emit_observation_frame(stage,pending_observation_elapsed,pending_observation,true,pending_observation_moved);},observation_failures);
  observation::best_effort([&](){return emit_observation_components(stage,pending_observation_elapsed,resolve(ledger.owned)==plane_flight::Seen::safe);},observation_failures);
 }
 void observe_before_destroy() noexcept {
  flush_observation();auto stage=observation_schedule.cleanup();if(stage==observation::Stage::none)return;++observation_attempts;
  ObservationFrame frame;capture_observation_phase(frame,false);frame.source_after=frame.source_before;frame.owned_after=frame.owned_before;
  double model[3];float scale=0;
  if(model_report.models_seeded&&ledger.finished_ready&&resolve(ledger.owned)==plane_flight::Seen::safe&&guarded_read(ledger.raw_owned+0x2268+0x8e0,model,sizeof model)&&::read(image_base+0xdc4c03c,scale)&&std::isfinite(scale)&&scale>0){
   frame.requested={model[2]*scale,-model[0]*scale,model[1]*scale};frame.requested_valid=observation::finite(frame.requested);
  }
  uint64_t elapsed=ledger.start_ms?now()-ledger.start_ms:0;
  observation::best_effort([&](){return emit_observation_frame(stage,elapsed,frame,false,false);},observation_failures);
  observation::best_effort([&](){return emit_observation_components(stage,elapsed,resolve(ledger.owned)==plane_flight::Seen::safe);},observation_failures);
 }
 plane_flight::Seen resolve(const plane_flight::Identity& id){
  uintptr_t item=0,object=0;int32_t serial=0;
  if(!item_for(id.index,item)||!::read(item,object)||!::read(item+0x10,serial))return plane_flight::Seen::unknown;
  if(!object||serial!=id.serial)return plane_flight::Seen::retired;
  return object==id.pointer?plane_flight::Seen::safe:plane_flight::Seen::unknown;
 }
 bool acquire(uintptr_t object,plane_flight::Identity& id,int kind){
  Header h;uintptr_t vt=0,cl=0,outer=0,level=0;uint32_t flags=0;
  if(!capture_header(object,h,false)||!::read(object,vt)||!::read(object+0x10,cl)||!::read(object+0x20,outer)||!::read(object+8,flags)||(flags&(0x10|0x20|0x40000000)))return false;
  if(kind==0){if(vt!=image_base+player_vtable||cl!=baseline.klass||!::read(baseline.world+0x30,level)||outer!=level||object==baseline.pawn||object==baseline.cdo)return false;}
  else if(kind==1){if(vt!=image_base+0xc88a868||outer!=ledger.raw_owned)return false;}
  else {uintptr_t expected=0;std::memcpy(&expected,source_config.parts.bytes.data()+0x10,8);if(cl!=expected||outer!=ledger.raw_owned)return false;}
  using Fn=int32_t(__fastcall*)(uintptr_t,int32_t);int32_t serial=reinterpret_cast<Fn>(image_base+serial_rva)(image_base+array_rva,h.index);
  uintptr_t item=0,actual=0;int32_t stored=0;if(serial<=0||!item_for(h.index,item)||!::read(item,actual)||actual!=object||!::read(item+0x10,stored)||serial!=stored)return false;
  id={object,h.index,serial};return true;
 }
 bool initial_barrier(uintptr_t actor){
  RawFlags f;if(!flag_snapshot(actor,f)||resolve(ledger.owned)!=plane_flight::Seen::safe||(f.begin&0xc)||(f.finish&9)||f.state>1)return false;
  *reinterpret_cast<unsigned char*>(actor+0x3f4)=0;*reinterpret_cast<unsigned char*>(actor+0x32)=static_cast<unsigned char>(f.start&~4u);
  *reinterpret_cast<unsigned char*>(actor+0x33)=0;*reinterpret_cast<unsigned char*>(actor+0x5a)=static_cast<unsigned char>(f.allow&~1u);
  // Pawn reflected AutoPossessPlayer/AutoPossessAI. Prevent constructor defaults
  // from attempting to acquire any controller during Finish/BeginPlay.
  *reinterpret_cast<unsigned char*>(actor+0x2a0)=0;*reinterpret_cast<unsigned char*>(actor+0x2a1)=0;
  return barrier_ok();
 }
 bool barrier_ok(){
  RawFlags f;unsigned char auto_player=0,auto_ai=0;
  return ledger.identified&&resolve(ledger.owned)==plane_flight::Seen::safe&&flag_snapshot(ledger.raw_owned,f)&&!f.active&&!f.state&&
   ::read(ledger.raw_owned+0x2a0,auto_player)&&!auto_player&&::read(ledger.raw_owned+0x2a1,auto_ai)&&!auto_ai&&
   (ledger.finish_entered||(!(f.start&4)&&!(f.allow&1)));
 }
 void close_actor_barrier(){
  if(resolve(ledger.owned)!=plane_flight::Seen::safe)return;
  uintptr_t fn=0;if(!::read(image_base+player_vtable+0x480,fn)||fn!=image_base+0x3fc34c0)return;
  *reinterpret_cast<unsigned char*>(ledger.raw_owned+0x3f4)=0;
  using Fn=void(__fastcall*)(uintptr_t,bool);reinterpret_cast<Fn>(fn)(ledger.raw_owned,false);
 }
 uintptr_t spawn(plane_flight::Ledger& receipt){
  alignas(16) double transform[12]={0,0,0,1,baseline.pose[0]+dx,baseline.pose[1]+dy,baseline.pose[2]+dz,0,1,1,1,0};
  alignas(16) unsigned char params[0x80]{};params[0x30]=1;params[0x31]=1;params[0x32]=4;uint32_t flags=8;std::memcpy(params+0x34,&flags,4);
  BridgeContext context;context.backend=this;context.ledger=&receipt;BridgeStorage storage{bridge_vtable,&context};
  uintptr_t invoke=reinterpret_cast<uintptr_t>(&bridge_invoke),capture=reinterpret_cast<uintptr_t>(&storage);std::memcpy(params+0x40,&invoke,8);std::memcpy(params+0x50,&capture,8);
  using Fn=uintptr_t(__fastcall*)(uintptr_t,uintptr_t,const void*,const void*);return reinterpret_cast<Fn>(image_base+spawn_rva)(baseline.world,baseline.klass,transform,params);
 }
 bool pending(){unsigned char state=0;uint32_t flags=0;return ::read(ledger.raw_owned+0x5d,state)&&::read(ledger.raw_owned+8,flags)&&((state&1)||(flags&0x40000000));}
 bool own_actor(){
  uintptr_t cls=0,controller=0,playerstate=0,net=0,parts=0;
  return resolve(ledger.owned)==plane_flight::Seen::safe&&same_header(headers[0],true)&&::read(ledger.raw_owned+0x10,cls)&&cls==baseline.klass&&
   ::read(ledger.raw_owned+baseline.pawn_offset,controller)&&!controller&&::read(ledger.raw_owned+0x2b0,playerstate)&&!playerstate&&
   ::read(ledger.raw_owned+0xed0,net)&&net==ledger.raw_network&&::read(ledger.raw_owned+0x1328,parts)&&parts==ledger.raw_parts;
 }
 bool matching_owned(uintptr_t object,const Header& source,uintptr_t outer){
  Header h;uintptr_t expected=0,actual=0,o=0;std::memcpy(&expected,source.bytes.data()+0x10,8);
  return object!=source.pointer&&capture_header(object,h,false)&&::read(object+0x10,actual)&&actual==expected&&::read(object+0x20,o)&&o==outer;
 }
 bool configure(){
  uintptr_t existing=0,activator=0;
  if(!own_actor()||!barrier_ok()||!::read(ledger.raw_owned+0x16a8,activator)||!matching_owned(activator,source_config.activator,ledger.raw_owned))return false;
  if(!::read(ledger.raw_owned+0x1328,existing)||existing)return false;
  struct IntArray{const int32_t*data;int32_t count,capacity;};
  IntArray selected{source_config.part_ids.data(),static_cast<int32_t>(source_config.part_ids.size()),static_cast<int32_t>(source_config.part_ids.size())},empty{};
  ledger.parts_entered=true;ledger.unknown_parts=true;
  using PartsFn=void(__fastcall*)(uintptr_t,const void*,const void*);reinterpret_cast<PartsFn>(image_base+0x7d4ad20)(ledger.raw_owned,&selected,&empty);
  if(!::read(ledger.raw_owned+0x1328,ledger.raw_parts)||!ledger.raw_parts)return false;
  ledger.parts_identified=acquire(ledger.raw_parts,ledger.parts,2);if(!ledger.parts_identified)return false;ledger.unknown_parts=false;
  std::vector<int32_t> actual,other;if(!integer_array(ledger.raw_parts+0x30,16,actual)||actual!=source_config.part_ids||!integer_array(ledger.raw_parts+0x40,16,other)||!other.empty())return false;
  ledger.network_entered=true;ledger.unknown_network=true;
  using Create=void(__fastcall*)(uintptr_t);reinterpret_cast<Create>(image_base+0x7d6ed30)(ledger.raw_owned);
  if(!::read(ledger.raw_owned+0xed0,ledger.raw_network)||!ledger.raw_network)return false;
  ledger.network_identified=acquire(ledger.raw_network,ledger.network,1);if(!ledger.network_identified)return false;ledger.unknown_network=false;
  if(!registry_absent()||!own_actor()||!barrier_ok())return false;
  // Only numeric selected configuration. No pointers, strings, arrays, model or component copies.
  const unsigned ints[]={0xf9c,0xfa4,0xfac,0xfb0,0xfb4,0xfc8,0xfcc,0xfd0,0xfd4,0xfdc};
  for(auto off:ints)std::memcpy(reinterpret_cast<void*>(ledger.raw_owned+off),source_config.scalars.data()+off-0xf98,4);
  for(unsigned off:{0xfa0u,0xfa1u,0xfa2u,0xfd8u})*reinterpret_cast<unsigned char*>(ledger.raw_owned+off)=source_config.scalars[off-0xf98];
  *reinterpret_cast<int32_t*>(ledger.raw_owned+0x3ab8)=source_config.row;
  *reinterpret_cast<unsigned char*>(ledger.raw_owned+0xed8)=2;
  *reinterpret_cast<uint64_t*>(ledger.raw_network+0x28)=owned_net_id;
  auto reader=[this](uintptr_t address,void* data,size_t size){return read(address,data,size);};
  auto writer=[this](uintptr_t address,const void* data,size_t size){return write(address,data,size);};
  if(!plane_flight_slots::copy_to_owned(reader,writer,baseline.pawn,ledger.raw_owned))return diagnostic_fail("owned_selection_ids_copy_failed_before_finish");
  selection_slots_copy_verified=true;
  return true;
 }
 bool ready_to_finish(){return own_actor()&&barrier_ok()&&registry_absent()&&source_configuration(false);}
 bool preseed(){return stage_current();}
 void finish(){
  alignas(16) double transform[12]={0,0,0,1,baseline.pose[0]+dx,baseline.pose[1]+dy,baseline.pose[2]+dz,0,1,1,1,0};
  using Fn=void(__fastcall*)(uintptr_t,const void*,bool,void*,unsigned char);reinterpret_cast<Fn>(image_base+0x3fdc360)(ledger.raw_owned,transform,false,nullptr,1);
 }
  bool component_is_a(uintptr_t component){
  uintptr_t root=0,klass=0,chain=0,entry=0;int32_t index=0,count=0;
  return ::read(image_base+0xe4addd8,root)&&pointer(root)&&::read(root+0x38,index)&&index>=0&&index<1024&&
   ::read(component+0x10,klass)&&pointer(klass)&&::read(klass+0x38,count)&&count>=index&&count<1024&&
   ::read(klass+0x30,chain)&&pointer(chain)&&::read(chain+static_cast<uintptr_t>(index)*8,entry)&&entry==root+0x30;
 }
 struct ComponentAccess {
  Backend& parent;Header identity;uintptr_t setter,getter;
  bool guard(){
   uintptr_t owner=0,vt=0,set=0,get=0;
   return parent.own_actor()&&same_header(identity,false)&&parent.component_is_a(identity.pointer)&&
    ::read(identity.pointer+0x90,owner)&&owner==ledger.raw_owned&&::read(identity.pointer,vt)&&
    ::read(vt+0x3d8,set)&&set==setter&&::read(vt+0x3e8,get)&&get==getter;
  }
  bool set_false(uintptr_t rva){
   if(setter!=image_base+rva||!guard())return false;
   using Fn=void(__fastcall*)(uintptr_t,bool);reinterpret_cast<Fn>(setter)(identity.pointer,false);return true;
  }
  bool read_state(plane_component_ticks::Kind kind,plane_component_ticks::State& state){
   if(!guard()||!::read(identity.pointer+0x3b,state.base_tick))return false;
   if(kind==plane_component_ticks::Kind::live&&!::read(identity.pointer+0xd3,state.custom_enabled))return false;
   if(kind==plane_component_ticks::Kind::mesh){
    if(!::read(identity.pointer+0xbd0,state.aux_registration))return false;
    if(state.aux_registration&&(!pointer(state.aux_registration)||!::read(state.aux_registration,state.aux_flags)))return false;
   }
   return true;
  }
 };
 bool components(std::vector<Header>& result,bool disable,bool best_effort=false){
  const uintptr_t set=ledger.raw_owned+0x218;unsigned char raw[0x38],after[0x38];
  if(!guarded_read(set,raw,sizeof raw))return component_fail("component_set_header_unreadable");
  uintptr_t data=0,external=0;int32_t num=0,capacity=0,bits=0,maxbits=0,free=0;
  std::memcpy(&data,raw,8);std::memcpy(&num,raw+8,4);std::memcpy(&capacity,raw+12,4);std::memcpy(&external,raw+0x20,8);
  std::memcpy(&bits,raw+0x28,4);std::memcpy(&maxbits,raw+0x2c,4);std::memcpy(&free,raw+0x34,4);
  if(num<0||num>512||bits!=num||capacity<num||capacity>4096||maxbits<bits||maxbits>4096||free<0||free>num||(!external&&bits>128)||!pointer(data))return component_fail("component_set_layout_invalid");
  const uintptr_t bitmap=external?external:set+0x10;if(!pointer(bitmap))return component_fail("component_set_bitmap_invalid");
  result.clear();unsigned active=0;bool valid=true;components_verified=0;
  for(int32_t i=0;i<bits;++i){uint32_t word=0;if(!::read(bitmap+static_cast<uintptr_t>(i/32)*4,word))return component_fail("component_set_bitmap_unreadable",i);if(!(word&(1u<<(i%32))))continue;
   ++active;uintptr_t component=0,owner=0,vt=0,setter=0,getter=0;
   if(!::read(data+static_cast<uintptr_t>(i)*16,component)||!pointer(component)||!component_is_a(component)||
    !::read(component+0x90,owner)||owner!=ledger.raw_owned||!::read(component,vt)||!::read(vt+0x3d8,setter)||
    !::read(vt+0x3e8,getter)||setter<image_base||getter<image_base){
     component_fail("component_owner_class_or_virtuals_unverified",i,component);if(best_effort){valid=false;continue;}return false;}
   Header h;if(!capture_header(component,h,false)){component_fail("component_header_identity_unverified",i,component,setter-image_base,getter-image_base);if(best_effort){valid=false;continue;}return false;}
   ComponentAccess access{*this,h,setter,getter};plane_component_ticks::Result checked;
   if(!plane_component_ticks::apply(access,{setter-image_base,getter-image_base},disable,checked)){
    component_fail(checked.error,i,component,setter-image_base,getter-image_base,checked.state);if(best_effort){valid=false;continue;}return false;
   }
   ++components_verified;result.push_back(h);
  }
  if(active!=static_cast<unsigned>(num-free)||!guarded_read(set,after,sizeof after)||std::memcmp(raw,after,sizeof raw))return component_fail("component_set_changed_during_pass");
  if(valid&&!component_failure_seen)component_failure="all_component_tick_domains_disabled";
  return valid;
 }
 bool disable_components(){return components(owned_components,true);}
 void quarantine_components(){std::vector<Header> checked;components(checked,true,true);}
 bool finished_graph(){
  if(!own_actor()||!registry_absent()||!barrier_ok()||!ledger.parts_identified||!ledger.network_identified||
   resolve(ledger.parts)!=plane_flight::Seen::safe||resolve(ledger.network)!=plane_flight::Seen::safe)return false;
  const uintptr_t p=ledger.raw_owned;uintptr_t act=0,target=0,indicator=0,weapon=0,nested=0,extra=0,link=0,table=0,data=0;
  unsigned char begun=0,initialized=0,role=0;uint64_t id=0;int32_t row=0,count=0;
  if(!::read(p+0x5d,begun)||(begun&0xc)!=8||!::read(p+0xed8,role)||role!=2||!::read(ledger.raw_network+0x28,id)||id!=owned_net_id||
   !::read(p+0x16a8,act)||!matching_owned(act,source_config.activator,p)||!::read(p+0x1ae8,target)||!matching_owned(target,source_config.target,p)||
   !::read(p+0x18d8,indicator)||!matching_owned(indicator,source_config.indicator,p)||!::read(indicator+0x1c0,link)||link!=p||
   !::read(p+0x5a08,link)||link!=indicator||!::read(p+0x5a30,link)||link!=target||
   !::read(act+0x2d0,link)||link!=p||!::read(act+0x2d8,link)||link!=target||!::read(act+0x579,initialized)||initialized!=1||
   !::read(act+0x2e0,weapon)||!matching_owned(weapon,source_config.weapon,p)||!::read(weapon+0xa8,nested)||!matching_owned(nested,source_config.nested,p)||
   !::read(act+0x2e8,extra)||!matching_owned(extra,source_config.extra,act)||
   !::read(p+0x3ab0,table)||!pointer(table)||!::read(table+0x18,data)||!pointer(data)||!::read(table+0x20,count)||count<1||count>4096||
   !::read(p+0x3ab8,row)||row<0||row>=count)return false;
  std::vector<Header> checked;return components(checked,false);
 }
 bool cleanup_guard(bool finished){return own_actor()&&(!finished||(finished_graph()&&registry_absent()));}
 bool guard(uint64_t token,uintptr_t source,uintptr_t p,uintptr_t net){
  return token==1&&source==baseline.pawn&&p==ledger.raw_owned&&net==ledger.raw_network&&same_header(headers[2],true)&&
   ledger.network_identified&&resolve(ledger.network)==plane_flight::Seen::safe&&own_actor()&&barrier_ok()&&registry_absent();
 }
 bool write(uintptr_t p,const void* value,size_t size){
  if(!size||size>8||!guard(1,baseline.pawn,ledger.raw_owned,ledger.raw_network))return false;
  unsigned char bytes[8];if(!guarded_read(p,bytes,size))return false;std::memcpy(reinterpret_cast<void*>(p),value,size);return true;
 }
 plane_initial_state::OwnedCaches caches(){
  plane_initial_state::OwnedCaches c;c.plane=ledger.raw_owned;c.network=ledger.raw_network;
  const unsigned offsets[]={0x98,0x140,0x150,0x160,0x170};for(unsigned i=0;i<5;++i)if(!::read(c.network+offsets[i],c.data[i]))return {};
  return c;
 }
 bool stage_current(){
  if(!verify_baseline(baseline,false)||!source_configuration(false))return false;
  const char* error=nullptr;
  if(!plane_initial_state::capture(*this,baseline.pawn,image_base,1,snapshot,error)){native_failure=error?error:"source_state_capture_failed";return false;}
  if(!plane_flight_state::translate(snapshot,dx,dy,dz)){native_failure="translation_failed";return false;}
  capture_timestamp=snapshot.timestamp;capture_scale=snapshot.scale;
  auto c=caches();bool ok=plane_initial_state::stage(*this,snapshot,c,stage_result);
  write_count=stage_result.scalar_writes;cache_readback=stage_result.readback;cache_error=stage_result.error;return ok;
 }
 bool reset_model(uintptr_t model){
  if(model!=ledger.raw_owned+0x3c60||!guard(1,baseline.pawn,ledger.raw_owned,ledger.raw_network))return false;
  using Fn=void(__fastcall*)(uintptr_t);reinterpret_cast<Fn>(image_base+0x4d344f0)(model);return true;
 }
 bool consume(uintptr_t network,uintptr_t model){
  if(network!=ledger.raw_network||(model!=ledger.raw_owned+0x2268&&model!=ledger.raw_owned+0x3c60)||!guard(1,baseline.pawn,ledger.raw_owned,ledger.raw_network))return false;
  using Fn=void(__fastcall*)(uintptr_t,uintptr_t);reinterpret_cast<Fn>(image_base+0x74d8c00)(network,model);return true;
 }
 bool input(uintptr_t model,uintptr_t inputs){
  auto c=caches();if(inputs!=c.data[4]+8||(model!=ledger.raw_owned+0x2268&&model!=ledger.raw_owned+0x3c60)||!guard(1,baseline.pawn,ledger.raw_owned,ledger.raw_network))return false;
  using Fn=void(__fastcall*)(uintptr_t,uintptr_t);reinterpret_cast<Fn>(image_base+0x4d32580)(model,inputs);return true;
 }
 bool seed(){
  if(!stage_current())return false;auto c=caches();
  if(!plane_flight_state::finalize(*this,snapshot,c,model_report)){native_failure="model_finalize_failed";return false;}
  native_failure="models_seeded_pose_pending";
  last_motion_ms=now();return pose_and_final_barrier();
 }
 bool pose_and_final_barrier(){
  if(!disable_components()||!finished_graph())return false;
  if(!sync_pose()){flush_observation();return false;}
  close_actor_barrier();bool ok=disable_components()&&finished_graph()&&verify_baseline(baseline,false);
  flush_observation();
  native_failure=ok?"pose_and_final_barrier_verified":"post_pose_barrier_failed";return ok;
 }
 bool sync_pose(){
  const uintptr_t model=ledger.raw_owned+0x2268;float q[4];double m[3],a[3];float scale=0;
  if(!guarded_read(model+0x8d0,q,sizeof q)||!guarded_read(model+0x8e0,m,sizeof m)||!::read(image_base+0xdc4c03c,scale)||!std::isfinite(scale)||scale<=0)return false;
  double norm=0;for(auto v:q){if(!std::isfinite(v))return false;norm+=static_cast<double>(v)*v;}if(norm<0.9||norm>1.1)return false;
  for(auto v:m)if(!std::isfinite(v))return false;
  using Angles=double*(__fastcall*)(const float*,double*);reinterpret_cast<Angles>(image_base+0x4d318a0)(q,a);
  constexpr double degrees=57.29577951308232;double world[3]={m[2]*scale,-m[0]*scale,m[1]*scale},rotation[3]={-a[0]*degrees,-a[1]*degrees,a[2]*degrees};
  for(unsigned i=0;i<3;++i)if(!std::isfinite(world[i])||std::abs(world[i])>1e9||!std::isfinite(rotation[i]))return false;
  uint64_t elapsed=ledger.running?now()-ledger.start_ms:0;auto stage=observation_schedule.pose(elapsed,!ledger.running);
  if(stage!=observation::Stage::none){
   ++observation_attempts;pending_observation={};pending_observation_stage=stage;pending_observation_elapsed=elapsed;
   pending_observation.requested={world[0],world[1],world[2]};pending_observation.requested_valid=true;capture_observation_phase(pending_observation,false);
  }
  using Move=bool(__fastcall*)(uintptr_t,const double*,const double*,bool,void*,unsigned char);
  bool moved=reinterpret_cast<Move>(image_base+0x3fdebc0)(ledger.raw_owned,world,rotation,false,nullptr,0);
  if(stage!=observation::Stage::none)pending_observation_moved=moved;return moved;
 }
 bool motion(){
  if(!finished_graph()||!stage_current())return false;
  uint64_t current=now();float dt=static_cast<float>(current-last_motion_ms)/1000.f;last_motion_ms=current;
  if(dt<0.001f)return true;if(dt>0.1f)dt=0.1f;
  using Update=void(__fastcall*)(uintptr_t,float);reinterpret_cast<Update>(image_base+0x7d6f0c0)(ledger.raw_owned,dt);
  close_actor_barrier();return pose_and_final_barrier();
 }

 bool destroy(uintptr_t p){observe_before_destroy();using Fn=bool(__fastcall*)(uintptr_t,bool);return reinterpret_cast<Fn>(image_base+destroy_rva)(p,false);}
};

void __fastcall bridge_invoke(void* p,uintptr_t* actor) {
    auto* context=static_cast<BridgeContext*>(p);
    if(context->self) { ++context->calls;context->matched=actor&&*actor==context->expected;return; }
    // Dispatcher gives a pointer to a local copy; it is not the Actor pointer itself.
    context->ledger->receipt(*context->backend,actor?*actor:0);
}

bool setup(void* module_address) {
    wchar_t marker[32],out[32768],expected[32768],actual[32768];
    if(!environment(L"AC8_COOP_RECON",marker,32)||std::wcscmp(marker,L"1")||
       !environment(L"AC8_COOP_RECON_OUTPUT",out,32768))return false;
    wcscpy_s(expected,32768,L"D:\\projects\\unreal-mod-tools\\profiles\\ac8-build25201480\\runtime\\ac8_plane_flight_probe_r4.dll");
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
        const std::wstring path=directory+L"\\plane-flight-lifecycle-events-r4.tsv";
        journal=CreateFileW(path.c_str(),FILE_APPEND_DATA,FILE_SHARE_READ,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(journal==INVALID_HANDLE_VALUE) return false;
    }
    return true;
}
void dispatch(unsigned action,void* module_address){
 if(!setup(module_address))return;
 if(!thread_id)thread_id=GetCurrentThreadId();
 if(thread_id!=GetCurrentThreadId()){status("error","wrong_game_callback_thread");return;}
 if(!fingerprints()){status("error","native_entry_fingerprint_mismatch");return;}
 Backend b;
 if(action==3){ledger.cleanup(b);status(ledger.status,ledger.reason);return;}
 if(action==2){ledger.tick(b);status(ledger.status,ledger.reason);return;}
 if(ledger.attempted){status("error","attempt_consumed_use_cleanup");return;}
 Request r;if(!request(r)){status("error","invalid_or_expired_request");return;}
 if(action==0){
  ready=false;baseline=r;ready_stamp=r.stamp;native_failure="preflight_started";
  if(!verify_baseline(r,true)||!source_configuration(true)||!bridge_selfcheck()){status("error",native_failure);return;}
  const char* error=nullptr;if(!plane_initial_state::capture(b,r.pawn,image_base,1,snapshot,error)){status("error",error?error:"initial_capture_failed");return;}
  ready_stamp=r.stamp;ready_tick=GetTickCount64();ready=true;native_failure="preflight_verified";status("ready","one_owned_remote_flight_trial_preflight");return;
 }
 std::string armed;
 if(!ready||GetTickCount64()-ready_tick>ttl*1000ULL||r.stamp!=ready_stamp||r.pc_offset!=baseline.pc_offset||r.pawn_offset!=baseline.pawn_offset||!read_file(L"plane-flight-armed.txt",armed)){
  status("error","missing_or_expired_arming");return;
 }
 while(!armed.empty()&&(armed.back()=='\n'||armed.back()=='\r'))armed.pop_back();
 if(armed!=ready_stamp){status("error","arming_stamp_mismatch");return;}
 if(!verify_baseline(r,false)||!source_configuration(false)){status("error",native_failure);return;}
 ready=false;baseline=r;ledger.run(b);status(ledger.status,ledger.reason);
}
int boundary(unsigned action,void* address){
 if(!TryAcquireSRWLockExclusive(&lock))return 0;
 // Only guarded reads use SEH. Native mutations and their faults are never swallowed.
 try{dispatch(action,address);}catch(...){
  if(!directory.empty()){Backend b;if(ledger.attempted)ledger.quarantine(b,"cpp_exception_state_retained_needs_game_close");status(ledger.attempted?"quarantine":"error","cpp_exception_state_retained");}
 }
 ReleaseSRWLockExclusive(&lock);return 0;
}

}

extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_flight_preflight(void*);
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_flight_preflight(void*) {return boundary(0,reinterpret_cast<void*>(&luaopen_ac8_flight_preflight));}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_flight_run(void*) {return boundary(1,reinterpret_cast<void*>(&luaopen_ac8_flight_preflight));}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_flight_tick(void*) {return boundary(2,reinterpret_cast<void*>(&luaopen_ac8_flight_preflight));}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_flight_cleanup(void*) {return boundary(3,reinterpret_cast<void*>(&luaopen_ac8_flight_preflight));}
