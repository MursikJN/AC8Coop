#include "cinema_vote_gate.h"
#include <cstdio>
#include <cstdlib>
unsigned checks=0;void check(bool value){++checks;if(!value){printf("Failed check %u\n",checks);exit(1);}}
int main(){
 ac8cinema::Gate g;check(!g.configure(0,true,false));check(g.configure(1,false,false));check(!g.decide(true)&&!g.requested);
 check(g.configure(1,true,false));check(!g.decide(false)&&!g.requested);check(!g.decide(true)&&g.requested&&!g.consumed);
 for(int i=0;i<10;++i)check(!g.decide(true)&&g.requested&&!g.consumed);
 check(g.configure(1,true,true));check(g.decide(false)&&g.consumed);check(!g.decide(true));check(g.configure(1,true,true));check(!g.decide(false));
 check(g.configure(2,true,false)&&!g.requested&&!g.authorized&&!g.consumed);check(!g.decide(true)&&g.requested);check(!g.configure(1,true,true));check(!g.decide(true));
 check(g.configure(2,true,true));check(g.decide(false));check(!g.decide(false));
 printf("%u cinema vote gate checks passed\n",checks);
}
