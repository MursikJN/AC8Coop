#include "guest_player_stage.cpp"
#include <cstdlib>
static unsigned checks=0;
static void check(bool x){++checks;if(!x){fprintf(stderr,"Staging request failed %u\n",checks);exit(1);}}
static std::string ticket(){return "format\tac8-guest-player-stage-v1\ncreated_unix\t"+std::to_string(std::time(nullptr))+"\nworld\t0x10000\ncontroller\t0x20000\nhost\t0x30000\nbaxter\t0x40000\nunit\t0x50000\nclass\t0x60000\ncdo\t0x70000\npc_pawn_offset\t0x350\npawn_pc_offset\t0x2c0\nslot\t1\n";}
static bool parse(const std::string&s){FILE*f=nullptr;fopen_s(&f,"guest-player-stage-request.tsv","wb");if(!f)exit(2);fwrite(s.data(),1,s.size(),f);fclose(f);Request r;return request(r);}
int main(){
 output=L".";uint64_t v=0;check(number("0x10000",v)&&v==65536);check(!number("-1",v));check(!number("+1",v));check(!number("18446744073709551616",v));check(!number("1x",v));check(!number("",v));
 auto good=ticket();check(parse(good));check(!parse(good+"extra\t0\n"));check(!parse(good+"slot\t1\n"));check(!parse(good.substr(0,good.size()-1)));
 auto change=[&](const std::string&a,const std::string&b){auto s=good;auto at=s.find(a);check(at!=std::string::npos);s.replace(at,a.size(),b);check(!parse(s));};
 change("slot\t1","slot\t2");change("world\t0x10000","world\t0x10001");change("world\t0x10000","world\t0");change("pc_pawn_offset\t0x350","pc_pawn_offset\t0x2008");change("pawn_pc_offset\t0x2c0","pawn_pc_offset\t-1");change("ac8-guest-player-stage-v1","ac8-guest-player-stage-v2");
 auto now=std::to_string(std::time(nullptr));change("created_unix\t"+now,"created_unix\t1");change("created_unix\t"+now,"created_unix\t"+std::to_string(std::time(nullptr)+10));
 check(!parse(std::string(2049,'x')));printf("%u deferred player request and freshness checks passed; no engine calls\n",checks);
}
