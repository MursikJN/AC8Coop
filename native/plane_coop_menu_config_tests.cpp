#include "plane_coop_menu_config.h"
#include <cstdio>
#include <cstdlib>
unsigned checks=0;
void check(bool value){++checks;if(!value){std::fprintf(stderr,"menu settings check %u failed\n",checks);std::exit(1);}}
int main(){
 const std::string good="format\tac8-coop-menu-v1\nrole\thost\npeer\t76561198000000002\nmission\t7\nplane\t23\n";
 ac8menu::Settings out;check(ac8menu::parse(good,out));check(out.role=="host"&&out.peer=="76561198000000002");
 auto guest=good;guest.replace(guest.find("host"),4,"guest");check(ac8menu::parse(guest,out));
 for(const auto& bad:{std::string{},good+"role\tguest\n",good+"x\ty\n",good+"\n",good.substr(0,good.find("plane\t")),std::string(257,'a')})check(!ac8menu::parse(bad,out));
 for(const auto& pair:{std::pair<std::string,std::string>{"host","server"},{"76561198000000002","7656119800000000a"},{"76561198000000002","00000000000000000"},{"mission\t7","mission\t6"},{"plane\t23","plane\t24"},{"ac8-coop-menu-v1","ac8-coop-menu-v2"}}){auto bad=good;bad.replace(bad.find(pair.first),pair.first.size(),pair.second);check(!ac8menu::parse(bad,out));}
 check(out.role=="guest");std::printf("%u menu configuration checks passed\n",checks);return 0;
}
