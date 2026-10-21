#include "guest_role_core.h"
#include <cassert>
#include <cstdio>
using namespace ac8role;
Readback staged(){
 Readback r;auto&c=r.context;c.world={0x10000,1,11};c.controller={0x20000,2,12};c.host={0x30000,3,13};c.npc={0x40000,4,14};c.unit={0x50000,5,15};c.player={0x60000,6,16};c.other_wingmen={Object{0x70000,7,17},Object{0x80000,8,18}};
 c.generation=10;c.revision=11;c.peer=12;c.remote_nonce=13;c.local_nonce=14;
 r.host_controller_preserved=r.host_plane_preserved=r.other_wingmen_preserved=true;
 r.player_class=r.player_physics=r.own_configuration=true;r.player_hidden=r.player_inactive=r.all_player_updates_fenced=true;
 r.player_alive=true;r.npc_active=true;r.active_planes=4;r.active_wingmen_ai=3;r.active_player_planes=1;return r;
}
Readback detached(){auto r=staged();r.npc_active=false;r.npc_retired=r.ai_links_detached=true;r.active_planes=3;r.active_wingmen_ai=2;
 r.role_lookup_routes_player=r.unit_events_route_player=r.hud_routes_player=r.wingman_orders_exclude_player=r.guest_world_loaded=true;return r;}
Readback active(){auto r=detached();r.player_hidden=r.player_inactive=false;r.active_planes=4;r.active_player_planes=2;return r;}
int main(){unsigned tests=0;ac8input::Assignment grant;
 {Adapter a;assert(!a.assignment(active(),grant)&&!ac8input::usable(grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));assert(!a.assignment(staged(),grant));assert(!a.lookup(staged()).valid());++tests;}
 {Adapter a;auto r=staged();r.context.peer=r.context.remote_nonce=r.context.local_nonce=0;assert(a.prepare(r));auto d=detached();d.context=r.context;assert(!a.activation_permitted(d));auto v=active();v.context=r.context;assert(!a.assignment(v,grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));assert(a.activation_permitted(detached()));assert(!a.assignment(detached(),grant));assert(a.assignment(active(),grant));ac8input::Lease l;assert(l.bind(grant));assert(same(a.lookup(active()),active().context.player));++tests;}
 // Required engine routing proofs cannot be replaced by labels or READY.
 for(auto flag:{&Readback::role_lookup_routes_player,&Readback::unit_events_route_player,&Readback::hud_routes_player,&Readback::wingman_orders_exclude_player,&Readback::guest_world_loaded,&Readback::ai_links_detached,&Readback::npc_retired,&Readback::host_controller_preserved,&Readback::host_plane_preserved,&Readback::other_wingmen_preserved,&Readback::player_class,&Readback::player_physics,&Readback::own_configuration}){
  Adapter a;assert(a.prepare(staged()));auto d=detached();d.*flag=false;assert(!a.activation_permitted(d));auto r=active();r.*flag=false;assert(!a.assignment(r,grant)&&!ac8input::usable(grant)&&!a.verified);++tests;
 }
 // Never grant a fifth plane or a still-active AI on the guest slot.
 for(auto flag:{&Readback::npc_active,&Readback::player_in_ai_arrays,&Readback::player_hidden,&Readback::player_inactive}){Adapter a;assert(a.prepare(staged()));auto r=active();r.*flag=true;assert(!a.assignment(r,grant));++tests;}
 for(auto n:{0u,3u,5u}){Adapter a;assert(a.prepare(staged()));auto r=active();r.active_planes=n;assert(!a.assignment(r,grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));auto r=active();r.active_wingmen_ai=3;assert(!a.assignment(r,grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));auto r=active();r.active_player_planes=1;assert(!a.assignment(r,grant));++tests;}
 // Address reuse, respawn, mission changes and settings changes invalidate grants.
 for(auto o:{&Context::world,&Context::controller,&Context::host,&Context::npc,&Context::unit,&Context::player}){
  Adapter a;assert(a.prepare(staged()));auto r=active();++(r.context.*o).serial;assert(!a.assignment(r,grant));++tests;
 }
 for(auto n:{&Context::generation,&Context::peer,&Context::remote_nonce,&Context::local_nonce}){Adapter a;assert(a.prepare(staged()));auto r=active();++(r.context.*n);assert(!a.assignment(r,grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));auto r=active();++r.context.revision;assert(!a.assignment(r,grant));++tests;}
 {Adapter a;auto r=staged();r.context.player=r.context.host;assert(!a.prepare(r));++tests;}
 {Adapter a;auto r=staged();r.context.player.index=r.context.host.index;assert(!a.prepare(r));++tests;}
 {Adapter a;auto r=staged();r.context.slot=2;assert(!a.prepare(r));++tests;}
 {Adapter a;assert(a.prepare(staged())&&a.assignment(active(),grant));auto r=active();++r.context.other_wingmen[0].serial;assert(!a.assignment(r,grant)&&!a.lookup(r).valid());++tests;}
 {Adapter a;assert(a.prepare(staged())&&a.assignment(active(),grant));a.clear();assert(!a.assignment(active(),grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));auto r=active();ac8input::Frame f;
  f.sender=r.context.peer;f.session=r.context.remote_nonce;f.echo=r.context.local_nonce;f.generation=r.context.generation;f.revision=r.context.revision;f.slot=1;f.aircraft=23;f.sequence=1;
  ac8input::Frame sampled;assert(a.accept(r,f,100));assert(a.sample(r,101,sampled)&&sampled.sequence==1);
  assert(!a.accept(r,f,200));assert(a.sample(r,400,sampled));assert(!a.sample(r,401,sampled));assert(!sampled.sequence);++tests;
  f.sequence=2;assert(a.accept(r,f,500));auto broken=r;broken.npc_active=true;assert(!a.sample(broken,501,sampled)&&!sampled.sequence&&!a.inputs.assigned);
  assert(!a.accept(r,f,502));f.sequence=3;assert(a.accept(r,f,503)&&a.sample(r,504,sampled));++tests;
 }
 {Adapter a;assert(a.prepare(staged())&&a.assignment(active(),grant));auto r=active();r.player_alive=false;r.player_death_confirmed=true;
  assert(!a.assignment(r,grant)&&a.spectating&&!a.inputs.assigned);assert(!a.assignment(active(),grant));assert(!a.prepare(staged()));++tests;}
 {Adapter a;assert(a.prepare(staged()));auto r=active();r.player_alive=false;r.player_death_confirmed=true;++r.context.world.serial;
  assert(!a.assignment(r,grant)&&!a.spectating);assert(a.assignment(active(),grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));auto r=active();r.player_alive=false;r.player_death_confirmed=true;assert(!a.assignment(r,grant));
  auto next=staged();++next.context.generation;assert(a.prepare(next)&&!a.spectating);auto next_active=active();next_active.context=next.context;assert(a.assignment(next_active,grant));++tests;}
 {Adapter a;assert(a.prepare(staged()));auto r=active();r.player_alive=false;assert(!a.assignment(r,grant)&&!a.spectating);++tests;}
 std::printf("guest role: %u replacement, stale identity, spectator and no-fifth-plane checks passed; engine bridge still required\n",tests);
}
