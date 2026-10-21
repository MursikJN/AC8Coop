#include "guest_story_route.h"
#include <cstdio>
#include <cstdlib>
int main(){
 unsigned checks=0;auto check=[&](bool v){++checks;if(!v)std::abort();};
 for(uintptr_t other:{uintptr_t(0x20000),uintptr_t(0x30000)}){
  check(ac8story::selected(0x10000,{0x10000,other},42,{7,8},42,99));
  check(ac8story::selected(0x10000,{other,0x10000},42,{7,8},99,8));
  check(!ac8story::selected(0x10000,{other},42,{7,8},42,8));
  check(!ac8story::selected(0x10000,{0x10000,other},42,{7,8},99,9));
 }
 check(!ac8story::selected(0x10000,{},42,{7},42,7));
 check(ac8story::selected(0x10000,{0x10000,0x10000},42,{},42,0));
 check(!ac8story::selected(0x10000,{0x10000},42,{},0,0));
 std::printf("%u story selector checks passed\n",checks);
}
