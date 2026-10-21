#include "guest_pilot_protocol.h"
#include "guest_pilot_input.h"
#include <cstdio>
#include <cstdlib>
using namespace ac8pilot;
Frame state(){Frame f;f.sender=1;f.session=10;f.echo=20;f.sequence=1;f.generation=7;f.source_us=50;f.count=4;f.flags=flight_only;
 for(unsigned i=0;i<4;++i){f.poses[i].role=i;f.poses[i].aircraft=i==1?23:7;f.poses[i].max_health=f.poses[i].health=200;f.poses[i].position={100,200,300};f.poses[i].rotation={0,0,0,1};}return f;}
int main(){unsigned checks=0;auto check=[&](bool v){++checks;if(!v){printf("FAIL %u\n",checks);std::abort();}};
 auto f=state();Frame decoded;auto bytes=encode(f);check(valid(f)&&decode(bytes.data(),bytes.size(),decoded));
 for(size_t i:{size_t(4),size_t(6),size_t(8),size_t(98),size_t(99),size_t(100),size_t(101),size_t(102),size_t(103),size_t(164),size_t(360),size_t(367)}){auto broken=bytes;broken[i]^=0x80;check(!decode(broken.data(),broken.size(),decoded));}
 for(size_t n=0;n<packet_size;++n)check(!decode(bytes.data(),n,decoded));
 auto bad=f;bad.poses[1].aircraft=7;check(!valid(bad));bad=f;bad.poses[0].position[0]=NAN;check(!valid(bad));bad=f;bad.poses[1].health=201;check(!valid(bad));
 Context ctx{1,2,10,20,true};Gate gate;gate.bind(ctx,7,1);Frame input;input.kind=Kind::input;input.sender=2;input.session=20;input.echo=10;input.sequence=2;input.generation=7;
 ac8input::Assignment assignment{2,20,10,7,1,1,23,true,true,true,true,true,true};
 check(!gate.accept(input,10,assignment));auto loaded=input;loaded.kind=Kind::loaded;loaded.sequence=1;check(gate.accept(loaded,11,assignment));check(gate.accept(input,12,assignment));
 check(!gate.accept(input,13,assignment));auto reordered=loaded;check(!gate.accept(reordered,14,assignment));
 ac8input::Frame sample;check(gate.lease.sample(312,sample));check(!gate.lease.sample(313,sample));
 ++input.sequence;input.generation=8;check(!gate.accept(input,314,assignment));input.generation=7;input.echo=11;check(!gate.accept(input,315,assignment));input.echo=10;
 gate.died();check(!gate.accept(input,316,assignment)&&gate.spectating);check(!gate.accept(loaded,317,assignment));
 Cadence c;check(!c.advance(1000000,false));check(c.advance(1016667,false)==1);check(!c.advance(1100000,true));check(c.advance(2100000,false)==6);check(!c.advance(2100000,false));
 RawInput raw;raw.up=raw.right=raw.throttle=true;check(axes(raw)==std::array<int16_t,5>{});raw.focused=true;auto control=axes(raw);check(control[0]==32767&&control[1]==32767&&control[3]==32767&&control[4]==0);
 raw.down=raw.left=true;control=axes(raw);check(!control[0]&&!control[1]);raw={};raw.focused=true;raw.stick_x=-32768;raw.stick_y=7849;control=axes(raw);check(control[1]==-32767&&control[0]==0);
 raw.trigger_left=255;raw.trigger_right=30;control=axes(raw);check(control[4]==32767&&control[3]==0);
 printf("%u pilot protocol, replay, timeout, spectator, input and cadence checks passed\n",checks);
}
