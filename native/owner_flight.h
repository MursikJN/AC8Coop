#pragma once
#ifndef AC8_OWNER_SIM_R30
#error Owner flight requires the R30 movement protocol; do not mix with host-input builds.
#endif
#include "guest_pilot_protocol.h"
#include "sortie_lifecycle.h"

namespace ac8owner {
// Movement authority only. Damage, death, weapons and mission events remain
// host authoritative. No pointer/model parameter/cache bytes cross the wire.
struct Receiver {
 ac8pilot::Context context{};uint64_t generation=0,sequence=0,source_us=0,received_ms=0;
 uint32_t revision=0;bool enabled=false,have=false,dead=false,prepared=false;
 ac8pilot::Frame previous{},latest{};uint64_t previous_ms=0;
 void bind(const ac8pilot::Context&c,uint64_t gen,uint32_t rev){*this={};context=c;generation=gen;revision=rev;prepared=c.host&&c.peer&&gen&&rev;}
 void release(bool both_ready){enabled=prepared&&both_ready&&!dead;}
 void stop(){enabled=have=prepared=false;previous={};latest={};}
 void died(){stop();dead=true;}
 bool accept(const ac8pilot::Frame&f,uint64_t now){
  if(!enabled||dead||!ac8pilot::valid(f)||f.kind!=ac8pilot::Kind::owner_state||!ac8pilot::matches(f,context)||f.generation!=generation||f.revision!=revision||
   f.sequence<=sequence||f.source_us<=source_us||(have&&now<received_ms))return false;
  previous=latest;previous_ms=received_ms;latest=f;sequence=f.sequence;source_us=f.source_us;received_ms=now;have=true;return true;
 }
 bool sample(uint64_t now,ac8pilot::Pose&pose)const {
  if(!enabled||!have||dead||now<received_ms||now-received_ms>300)return false;
  pose=latest.poses[0];if(!previous.sequence||received_ms<=previous_ms)return true;
  const auto elapsed=received_ms-previous_ms;
  const double t=std::clamp((double(now)-75.0-double(previous_ms))/double(elapsed),0.0,1.0);
  for(unsigned i=0;i<3;++i)pose.position[i]=previous.poses[0].position[i]+t*(pose.position[i]-previous.poses[0].position[i]);
  double dot=0,norm=0;for(unsigned i=0;i<4;++i)dot+=double(previous.poses[0].rotation[i])*pose.rotation[i];
  for(unsigned i=0;i<4;++i){pose.rotation[i]=float(previous.poses[0].rotation[i]*(1-t)+pose.rotation[i]*t*(dot<0?-1:1));norm+=double(pose.rotation[i])*pose.rotation[i];}
  if(norm<1e-12)return false;
  for(auto&v:pose.rotation)v=float(v/std::sqrt(norm));return true;
 }
};

// The game backend must initialize and own its local flight model first.
// Crucially, a network send/host echo is never a prerequisite for local step().
// Backend.prepare() must refuse if stock model initialization is unverified.
template<class Backend>class LocalPilot {
 Backend&backend;ac8pilot::Cadence cadence{};ac8sortie::Key key{};ac8pilot::Context context{};
 bool active=false,held=true,quarantined=false,resources=false;uint64_t sequence=0,last_publish_us=0;
public:
 const char*detail="not_prepared";uint64_t steps=0,send_failures=0;
 explicit LocalPilot(Backend&b):backend(b){}
 bool prepare(const ac8sortie::Key&next,const ac8pilot::Context&binding){
  if(active||quarantined||!next.valid()||binding.host||!binding.local||!binding.peer||!binding.nonce||!binding.remote||binding.local==binding.peer)return false;
  resources=true;
  if(!backend.prepare(next)){const auto why=backend.reason();stop();detail=why;return false;}
  key=next;context=binding;cadence={};active=true;held=true;steps=sequence=last_publish_us=0;detail="local_model_prepared_wait_barrier";return true;
 }
 void release(bool both_ready){held=!both_ready;}
 bool running()const{return active;}
 template<class Publish>bool tick(uint64_t now,const ac8input::Frame&input,bool paused,Publish publish){
  if(!active)return false;
  if(!backend.valid()){stop();detail="local_model_identity_lost";return false;}
  const bool allowed=!held&&!paused;
  const auto count=cadence.advance(now,!allowed);
  if(!count)return true;
  if(input.sender!=context.local||input.session!=context.nonce||input.echo!=context.remote||input.slot!=1||input.generation!=key.generation||input.revision!=key.revision||!ac8input::valid(input)){stop();detail="local_input_assignment_changed";return false;}
  // Run immediately. An unavailable network can drop this publication but
  // cannot delay the already authorized local physics/camera calculation.
  if(!backend.step(input,count)){stop();detail="local_native_step_failed";return false;}steps+=count;
  ac8pilot::Frame f;f.kind=ac8pilot::Kind::owner_state;f.generation=key.generation;f.revision=key.revision;f.count=1;f.source_us=now;
  if(!backend.snapshot(f.poses[0],f.velocity)||!backend.camera(f.poses[0])){stop();detail="local_pose_or_camera_failed";return false;}
  f.poses[0].health=f.poses[0].max_health=0;f.poses[0].flags=0;
  if(now>=last_publish_us&&now-last_publish_us>=33333){
   if(sequence==UINT64_MAX){stop();detail="owner_sequence_exhausted";return false;}
   f.sequence=++sequence;f.session=context.nonce;f.sender=context.local;f.echo=context.remote;
   if(!ac8pilot::valid(f)){stop();detail="invalid_local_owner_snapshot";return false;}
   if(!publish(f))++send_failures;last_publish_us=now;
  }
  detail="local_model_steps_without_host_echo";return true;
 }
 bool stop(){
  held=true;active=false;cadence={};key={};context={};
  // Returning false means ownership is quarantined; caller must not reuse IDs.
  const bool released=!resources||backend.release();quarantined=!released;resources=!released;detail=released?"local_model_released":"local_cleanup_pending_no_id_reuse";return released;
 }
};
}
