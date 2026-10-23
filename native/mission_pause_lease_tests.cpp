#include "mission_pause_lease.h"
#include <cassert>
#include <cstdio>
int main(){
 ac8pause::Lease l;uint32_t f=0x10;
 assert(l.acquire(f)&&f==0x18);assert(l.acquire(f)&&f==0x18);
 f=0x210;assert(l.acquire(f)&&f==0x218);
 l.release(f);assert(f==0x210);l.release(f);assert(f==0x210);
 f=8;assert(!l.acquire(f)&&f==8&&!l.held);l.release(f);assert(f==8);
 puts("7 pause ownership checks passed");
 ac8pause::DisconnectLease d;f=8;
 assert(d.acquire(f)&&f==40);assert(d.acquire(f)&&f==40);
 f|=16;d.release(f);assert(f==24);d.release(f);assert(f==24);
 f=32;assert(!d.acquire(f)&&f==32&&!d.held);d.release(f);assert(f==32);
 puts("6 disconnect reason ownership checks passed");
}
