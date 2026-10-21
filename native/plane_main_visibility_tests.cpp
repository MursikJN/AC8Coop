#include "plane_main_visibility.h"
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <stdexcept>
#include <fstream>
#include <iterator>
#include <regex>
namespace vis=plane_main_visibility;
namespace obs=plane_flight_observations;
constexpr uintptr_t image=0x140000000;
obs::Identity id(uintptr_t p,uintptr_t outer=0){obs::Identity i;i.pointer=p;i.outer=outer;i.index=static_cast<int32_t>(p/0x1000);i.serial=3;i.klass=0x80000;i.vtable=image+vis::main_vtable_rva;return i;}
obs::Scene scene(uintptr_t p,uintptr_t actor,uint8_t flags){
 obs::Scene s;s.identity=id(p,actor);s.identity_valid=s.scene_verified=s.owner_matches=s.flags_valid=true;
 s.owner=actor;s.raw_flags={flags,0,8,2,0,0,0,0,0};return s;
}
vis::Snapshot baseline(){
 vis::Snapshot s;s.source=id(0x10000);s.owned=id(0x20000);
 s.source_main=scene(0x30000,0x10000,0x61);s.source_secondary=scene(0x40000,0x10000,0x43);
 s.main=scene(0x50000,0x20000,0x41);s.secondary=scene(0x60000,0x20000,0x43);s.barriers=true;return s;
}
struct Mock {
 vis::Snapshot state=baseline();unsigned captures=0,calls=0;uintptr_t called_pointer=0;
 bool fingerprint=true,pre_read=true,post_read=true,throws=false;
 std::function<void(vis::Snapshot&)> effect=[](vis::Snapshot& s){s.main.raw_flags[0]|=0x20;};
 bool capture(vis::Snapshot& out){out=state;return ++captures==1?pre_read:post_read;}
 bool setter_ready(const vis::Snapshot&){return fingerprint;}
 void set_main(uintptr_t p){++calls;called_pointer=p;if(throws)throw std::runtime_error("native boundary substitute");effect(state);}
};
unsigned checks=0;
void check(bool ok,const char* label){++checks;if(!ok){std::printf("FAIL %s\n",label);std::exit(1);}}
void reject_before(const std::function<void(vis::Snapshot&)>& change,const char* label){
 Mock b;vis::Report r;change(b.state);check(!vis::enable(b,image,r)&&!b.calls&&!r.called,label);
}
void reject_after(const std::function<void(vis::Snapshot&)>& change,const char* label){
 Mock b;vis::Report r;b.effect=[&](vis::Snapshot& s){s.main.raw_flags[0]|=0x20;change(s);};
 check(!vis::enable(b,image,r)&&b.calls==1&&r.called&&!r.verified,label);
 check(!vis::enable(b,image,r)&&b.calls==1,"failed mutation cannot be retried");
}
std::array<unsigned char,9> fixture_flags(const std::string& json,const char* key){
 std::smatch match;std::regex field(std::string("\"")+key+"\"\\s*:\\s*\"([0-9a-f]{18})\"");
 if(!std::regex_search(json,match,field)){std::printf("Missing fixture key %s\n",key);std::exit(1);}
 std::array<unsigned char,9> out{};for(unsigned i=0;i<9;++i)out[i]=static_cast<unsigned char>(std::stoul(match[1].str().substr(i*2,2),nullptr,16));return out;
}
int main(int argc,char** argv){
 check(argc==2,"independent recorded-memory fixture required");
 std::ifstream file(argv[1],std::ios::binary);check(file.good(),"open recorded R5 fixture");
 std::string json((std::istreambuf_iterator<char>(file)),std::istreambuf_iterator<char>());
 {Mock b;vis::Report r;
  b.state.main.raw_flags=fixture_flags(json,"main_flags_hex");
  b.state.source_main.raw_flags=fixture_flags(json,"source_main_flags_hex");
  b.state.secondary.raw_flags=fixture_flags(json,"secondary_flags_hex");
  b.state.source_secondary.raw_flags=fixture_flags(json,"source_secondary_flags_hex");
  check(b.state.main.raw_flags[2]==8&&b.state.main.raw_flags[8]==0,"recorded +18A and +190 offsets distinguished");
  check(vis::enable(b,image,r)&&b.calls==1&&r.verified,"actual R5 raw bytes permit one mock setter and verified readback");}
 {Mock b;vis::Report r;check(vis::enable(b,image,r)&&r.verified&&b.calls==1&&b.called_pointer==0x50000,"only owned main passed to setter");
  check(r.before.main.raw_flags[0]==0x41&&r.after.main.raw_flags[0]==0x61,"raw before and after retained");
  check(b.state.secondary.raw_flags[0]==0x43&&b.state.source_main.raw_flags[0]==0x61,"secondary and source unchanged");
  check(!vis::enable(b,image,r)&&b.calls==1,"successful mutation cannot be retried");}
 reject_before([](auto& s){s.main.identity_valid=false;},"invalid main GU identity");
 reject_before([](auto& s){s.main.identity.serial=-1;},"invalid serial");
 reject_before([](auto& s){s.main.identity.flags=0x40000000;},"pending kill main");
 reject_before([](auto& s){s.main.scene_verified=false;},"scene class not verified");
 reject_before([](auto& s){s.main.flags_valid=false;},"unreadable flags");
 reject_before([](auto& s){s.main.owner=s.source.pointer;},"foreign owner");
 reject_before([](auto& s){s.main.identity.outer=s.source.pointer;},"foreign Outer");
 reject_before([](auto& s){s.main.identity.vtable+=8;},"unexpected vtable");
 reject_before([](auto& s){s.main.identity.klass+=8;},"source class mismatch");
 reject_before([](auto& s){s.secondary.identity.klass+=8;},"secondary class mismatch");
 reject_before([](auto& s){s.main.identity.pointer=s.secondary.identity.pointer;},"main aliases secondary");
 reject_before([](auto& s){s.main.identity.pointer=s.source_main.identity.pointer;},"main aliases source");
 reject_before([](auto& s){s.source.pointer=s.owned.pointer;},"source aliases owned Actor");
 reject_before([](auto& s){s.main.raw_flags[0]=0x61;},"unexpected already visible main");
 reject_before([](auto& s){s.main.raw_flags[1]=8;},"hidden main");
 reject_before([](auto& s){s.main.raw_flags[8]=4;},"unreviewed setter side effect branch");
 reject_before([](auto& s){s.source_main.raw_flags[0]&=~0x20;},"source main not visible");
 reject_before([](auto& s){s.source_secondary.raw_flags[0]=0x63;},"source secondary outside contract");
 reject_before([](auto& s){s.secondary.raw_flags[0]=0x63;},"secondary outside contract");
 reject_before([](auto& s){s.active=1;},"Actor active");
 reject_before([](auto& s){s.barriers=false;},"ticks not closed");
 {Mock b;vis::Report r;b.fingerprint=false;check(!vis::enable(b,image,r)&&!b.calls,"fingerprint failure prevents native call");}
 {Mock b;vis::Report r;b.pre_read=false;check(!vis::enable(b,image,r)&&!b.calls,"failed pre-read prevents call");}
 {Mock b;vis::Report r;b.post_read=false;check(!vis::enable(b,image,r)&&b.calls==1&&!r.verified,"failed post-read not success");}
 reject_after([](auto& s){s.main.raw_flags[0]=0x41;},"no visible bit readback");
 reject_after([](auto& s){s.main.raw_flags[2]^=1;},"unrelated main flag changed");
 reject_after([](auto& s){s.main.raw_flags[1]|=8;},"hidden gate remains closed");
 reject_after([](auto& s){s.source_main.raw_flags[0]^=0x20;},"source flags changed");
 reject_after([](auto& s){s.source_secondary.raw_flags[3]^=1;},"source secondary flags changed");
 reject_after([](auto& s){s.secondary.raw_flags[0]^=0x20;},"owned secondary flags changed");
 reject_after([](auto& s){s.main.identity.serial++;},"main identity replaced");
 reject_after([](auto& s){s.owned.serial++;},"Actor identity replaced");
 reject_after([](auto& s){s.active=1;},"callback enabled Actor");
 reject_after([](auto& s){s.barriers=false;},"callback enabled component tick");
 reject_after([](auto& s){s.gate=0x70000;s.gate_byte=0;},"nonnull A0 gate closed");
 {Mock b;vis::Report r;b.state.gate=0x70000;b.state.gate_byte=1;check(vis::enable(b,image,r),"nonnull open A0 gate accepted");}
 {Mock b;vis::Report r;b.throws=true;bool caught=false;try{vis::enable(b,image,r);}catch(const std::runtime_error&){caught=true;}
  check(caught&&r.called&&!r.verified,"mutation fault not swallowed or retried");}
 std::printf("%u main visibility checks passed\n",checks);return 0;
}
