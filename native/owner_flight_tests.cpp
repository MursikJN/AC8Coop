#define AC8_STEAM_COOP_R27
#define AC8_OWNER_SIM_R30
#define AC8_MISSION_SYNC_R26
#define AC8_CINEMA_SYNC_R28
#define AC8_SESSION_POLICY_R29
#include "owner_flight.h"
#include "shared_session_protocol.h"
#include "steam_invite_core.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
using namespace ac8pilot;
static unsigned checks=0;
static void check(bool v){++checks;if(!v){std::printf("FAIL owner check %u\n",checks);std::abort();}}
static Frame owner(){
 Frame f;f.kind=Kind::owner_state;f.sender=2;f.session=20;f.echo=10;f.sequence=1;f.generation=7;f.source_us=1000000;f.count=1;
 f.poses[0].role=1;f.poses[0].aircraft=23;f.poses[0].position={100,200,300};f.poses[0].rotation={0,0,0,1};f.poses[0].speed=100;f.velocity={100,0,0};return f;
}
static ac8sortie::Manifest manifest(){
 ac8sortie::Manifest m;m.key={10,7,1};m.members[0]={1,4,0,7,"opaque-host"};m.members[1]={2,9,1,23,"opaque-guest"};return m;
}
// Test double proves control flow/order, NOT Aerodynamic/native physics.
struct TestModel {
 bool permitted=true,live=false,released=true;unsigned calls=0,camera_calls=0,release_calls=0;
 Pose pose=owner().poses[0];
 bool prepare(const ac8sortie::Key&){live=permitted;return live;}
 const char*reason(){return "stock_initialization_unverified";}
 bool valid(){return live;}
 bool step(const ac8input::Frame&i,unsigned n){++calls;pose.position[0]+=double(i.axes[1])*n;return true;}
 bool snapshot(Pose&p,std::array<double,3>&v){p=pose;v={100,0,0};return true;}
 bool camera(const Pose&p){++camera_calls;return p.position==pose.position;}
 bool release(){++release_calls;live=false;return released;}
};
int main(){
 check(ac8session::protocol_version==8);
 ac8session::Frame room;room.sender=1;room.session=10;room.echo=20;room.sequence=1;room.op=ac8session::Op::ready;
 auto room_wire=ac8session::encode(room);ac8session::Frame room_read;check(ac8session::decode(room_wire.data(),room_wire.size(),room_read));
 room_wire[4]=7;check(!ac8session::decode(room_wire.data(),room_wire.size(),room_read));
 auto invitation=ac8invite::encode(76561198000000001ull);uint64_t invited=0;
 check(invitation.find("ac8coop:v8:")==0&&ac8invite::decode(invitation.c_str(),invitation.size()+1,invited));
 invitation[9]='7';check(!ac8invite::decode(invitation.c_str(),invitation.size()+1,invited));
 auto f=owner();auto b=encode(f);Frame decoded;
 check(packet_size==392&&pilot_version==3&&valid(f)&&decode(b.data(),b.size(),decoded)&&decoded.velocity==f.velocity);
 for(size_t n=0;n<packet_size;++n)check(!decode(b.data(),n,decoded));
 for(size_t index:{size_t(4),size_t(6),size_t(8),size_t(98),size_t(103)}){auto bad=b;bad[index]^=0x80;check(!decode(bad.data(),bad.size(),decoded));}
 auto invalid=f;invalid.poses[0].health=1;check(!valid(invalid));invalid=f;invalid.poses[0].max_health=1;check(!valid(invalid));
 invalid=f;invalid.poses[0].role=0;check(!valid(invalid));invalid=f;invalid.poses[0].position[0]=NAN;check(!valid(invalid));
 invalid=f;invalid.velocity[0]=INFINITY;check(!valid(invalid));invalid=f;invalid.axes[0]=1;check(!valid(invalid));
 invalid=f;invalid.flags=dead;check(!valid(invalid));invalid=f;invalid.poses[1]=invalid.poses[0];check(!valid(invalid));
 invalid=f;invalid.kind=Kind::input;invalid.count=0;check(!valid(invalid));
 check(outgoing_kind(false,Kind::owner_state)&&!outgoing_kind(true,Kind::owner_state)&&!outgoing_kind(false,Kind::input));
 ac8owner::Receiver receiver;receiver.bind({1,2,10,20,true},7,1);Pose p;
 check(!receiver.accept(f,99));receiver.release(true);
 check(!receiver.sample(10,p));check(receiver.accept(f,100));check(receiver.sample(100,p)&&p.position==f.poses[0].position);
 check(!receiver.accept(f,101));auto wrong=f;wrong.sequence=2;wrong.source_us++;
 wrong.sender=3;check(!receiver.accept(wrong,101));wrong=f;wrong.sequence=2;wrong.source_us++;wrong.echo=11;check(!receiver.accept(wrong,101));
 wrong=f;wrong.sequence=2;wrong.source_us++;wrong.session=21;check(!receiver.accept(wrong,101));
 wrong=f;wrong.sequence=2;wrong.source_us++;wrong.generation=8;check(!receiver.accept(wrong,101));
 wrong=f;wrong.sequence=2;wrong.source_us++;wrong.revision=2;check(!receiver.accept(wrong,101));
 wrong=f;wrong.sequence=2;check(!receiver.accept(wrong,101)); // newer sequence, stale owner clock
 f.sequence=2;f.source_us+=100000;f.poses[0].position[0]=200;f.poses[0].rotation={0,0,0,-1};
 check(receiver.accept(f,200));check(receiver.sample(225,p)&&std::fabs(p.position[0]-150)<1e-6&&std::fabs(p.rotation[3]-1)<1e-6);
 check(receiver.sample(500,p));check(!receiver.sample(501,p)); // 300 ms freeze, no unlimited extrapolation
 receiver.died();++f.sequence;++f.source_us;check(!receiver.accept(f,502)&&!receiver.sample(502,p));
 receiver.bind({1,2,30,40,true},8,1);check(!receiver.accept(f,503));

 using namespace ac8sortie;Lifecycle life;auto m=manifest();check(m.valid()&&life.begin(m));
 auto broken=m;broken.members[1].member_id=4;check(!broken.valid());broken=m;broken.members[1].profile=m.members[0].profile;check(!broken.valid());
 broken=m;broken.members[1].member_id=UINT32_MAX;check(!broken.valid());broken=m;broken.members[1].role=0;check(!broken.valid());
 broken=m;broken.members[1].mod_count=2;broken.members[1].mods[0]=broken.members[1].mods[1]=5;check(!broken.valid());
 broken=m;broken.members[1].weapon1=65536;check(!broken.valid());
 check(life.ready(0,m.key,true)&&life.ready(1,m.key,true));auto old=life.token();old.confirmed=true;
 ++m.key.revision;m.members[1].weapon1=16;check(life.edit(m));check(life.manifest().members[1].weapon1==16);check(!life.commit(0,m.key));check(!life.ready(1,old.key,true));
 check(life.ready(0,m.key,true)&&life.ready(1,m.key,true));check(!life.commit(1,m.key));check(life.commit(0,m.key));check(!life.commit(0,m.key));
 check(!life.edit(m)&&!life.controls());auto receipt=life.token();receipt.confirmed=true;
 check(!life.quiesced(old,true));check(!life.quiesced(receipt,false));check(life.quiesced(receipt,true));
 check(!life.detached(receipt,true,false,true));check(!life.detached(receipt,true,true,false));check(!life.detached(receipt,false,true,true));
 check(life.detached(receipt,true,true,true));check(!life.spawned(receipt,2,3,true,true));check(!life.spawned(receipt,2,2,false,false));
 check(life.spawned(receipt,2,2,false,true));check(!life.loaded(0,receipt,true,true,false,true));
 check(life.loaded(0,receipt,true,true,true,true)&&!life.controls());check(life.loaded(0,receipt,true,true,true,true)&&!life.controls());
 check(life.loaded(1,receipt,true,true,true,true)&&life.controls());check(life.stop()&&!life.controls());auto cleanup=life.token();cleanup.confirmed=true;
 check(life.stop()&&life.ticket()==cleanup.ticket);check(!life.released(receipt,true,true,true,true,true));
 check(!life.released(cleanup,true,true,false,true,true));check(!life.begin(m));
 check(life.released(cleanup,true,true,true,true,true));check(!life.begin(m));++m.key.generation;check(life.begin(m));check(!life.quiesced(receipt,true));

 TestModel model;ac8owner::LocalPilot<TestModel> pilot(model);ac8input::Frame input;
 input.sender=2;input.session=20;input.echo=10;input.sequence=1;input.generation=7;input.revision=1;input.slot=1;input.aircraft=23;input.axes[1]=100;
 unsigned sent=0;std::vector<Frame> network;
 auto drop=[&](const Frame&packet){++sent;network.push_back(packet);return false;};
 const Context binding{2,1,20,10,false};
 check(pilot.prepare({10,7,1},binding));check(pilot.tick(1000000,input,false,drop)&&!model.calls);
 check(pilot.tick(1016667,input,false,drop)&&!model.calls); // barrier holds
 pilot.release(true);check(pilot.tick(1033334,input,false,drop));
 check(model.calls==1&&model.pose.position[0]==200&&model.camera_calls==1&&sent==1&&pilot.send_failures==1);
 check(pilot.tick(1050001,input,false,drop)&&model.pose.position[0]==300); // zero ACKs; still immediate
 check(pilot.tick(1200000,input,true,drop)&&model.calls==2); // no catch-up burst after pause
 check(pilot.tick(1216667,input,false,drop)&&model.calls==3);
 check(!network.empty()&&valid(network.front())&&network.front().kind==Kind::owner_state&&network.front().poses[0].health==0);
 ++input.revision;check(!pilot.tick(1233334,input,false,drop)&&!pilot.running()&&model.release_calls==1);
 TestModel blocked;blocked.permitted=false;ac8owner::LocalPilot<TestModel> refused(blocked);
 check(!refused.prepare({10,7,1},binding)&&!refused.running()&&blocked.calls==0);
 TestModel pending;pending.released=false;ac8owner::LocalPilot<TestModel> quarantined(pending);
 check(quarantined.prepare({10,7,1},binding));check(!quarantined.stop());check(!quarantined.prepare({10,8,1},binding));
 std::printf("%u owner protocol, local-step ordering, replay, delayed loading and cleanup checks passed (test backend, no game physics)\n",checks);
}
