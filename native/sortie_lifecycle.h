#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <limits>

// Adapter contract, not a guessed native matchmaking ABI. Receipts must be
// produced by a backend after readback on its game thread. Session/epoch IDs
// here are mod IDs; they must never be cast to native member/profile IDs.
namespace ac8sortie {
struct Key {
 uint64_t session=0,generation=0;uint32_t revision=0;
 bool valid()const{return session&&generation&&revision;}
 bool operator==(const Key&b)const{return session==b.session&&generation==b.generation&&revision==b.revision;}
};
struct Member {
 uint64_t peer=0;uint32_t member_id=UINT32_MAX,role=0,aircraft=0;
 std::string profile; // opaque native userid, never atoi()/SteamID truncation
 uint32_t weapon1=0,weapon2=0,mod_count=0;std::array<uint32_t,8>mods{};
};
struct Manifest {
 Key key;std::array<Member,2> members{};
 uint32_t mission=7,difficulty=1; // internal Mission007; display mission 6
 bool valid()const {
  if(!key.valid()||mission!=7||difficulty>255||members[0].peer==members[1].peer||members[0].member_id==members[1].member_id||members[0].profile==members[1].profile)return false;
  for(unsigned i=0;i<2;++i){const auto&m=members[i];if(!m.peer||m.member_id==UINT32_MAX||m.role!=i||!m.aircraft||m.aircraft>65535||m.profile.empty()||m.profile.size()>256)return false;}
  for(const auto&m:members){
   if(m.weapon1>65535||m.weapon2>65535||m.mod_count>m.mods.size())return false;
   for(size_t i=0;i<m.mods.size();++i){
    if(i>=m.mod_count){if(m.mods[i])return false;}
    else{if(!m.mods[i]||m.mods[i]>65535)return false;for(size_t j=0;j<i;++j)if(m.mods[i]==m.mods[j])return false;}
   }
  }
  return members[1].aircraft==23;
 }
};
enum class Phase {idle,editing,quiescing,detaching,spawning,loading,flight,stopping,closed};
struct Receipt {Key key;uint64_t ticket=0;bool confirmed=false;};
class Lifecycle {
 Manifest manifest_{};uint64_t ticket_=0;uint8_t ready_=0,loaded_=0;Phase phase_=Phase::idle;
 bool receipt(const Receipt&r)const{return r.confirmed&&r.ticket==ticket_&&r.key==manifest_.key;}
 bool advance_ticket(){if(ticket_==UINT64_MAX)return false;++ticket_;return true;}
public:
 const char* detail="idle";
 Phase phase()const{return phase_;}uint64_t ticket()const{return ticket_;}
 const Manifest&manifest()const{return manifest_;}
 Receipt token()const{return {manifest_.key,ticket_,false};}
 bool editable()const{return phase_==Phase::editing;}
 bool controls()const{return phase_==Phase::flight&&loaded_==3;}
 bool begin(const Manifest&m){
  if((phase_!=Phase::idle&&phase_!=Phase::closed)||!m.valid())return false;
  if(phase_==Phase::closed&&m.key.session==manifest_.key.session&&m.key.generation<=manifest_.key.generation)return false;
  if(!advance_ticket())return false;
  manifest_=m;ready_=loaded_=0;phase_=Phase::editing;detail="editing_two_members";return true;
 }
 bool edit(const Manifest&m){
  if(!editable()||!m.valid()||m.key.session!=manifest_.key.session||m.key.generation!=manifest_.key.generation||m.key.revision<=manifest_.key.revision)return false;
  for(unsigned i=0;i<2;++i)if(m.members[i].peer!=manifest_.members[i].peer||m.members[i].member_id!=manifest_.members[i].member_id||m.members[i].profile!=manifest_.members[i].profile)return false;
  if(!advance_ticket())return false;
  manifest_=m;ready_=loaded_=0;detail="selection_changed_ready_reset";return true;
 }
 bool ready(unsigned peer,const Key&key,bool value){
  if(!editable()||peer>1||!(key==manifest_.key))return false;
  const auto mask=uint8_t(1u<<peer);ready_=value?uint8_t(ready_|mask):uint8_t(ready_&~mask);return true;
 }
 bool commit(unsigned peer,const Key&key){
  if(peer||!editable()||!(key==manifest_.key)||ready_!=3)return false;
  phase_=Phase::quiescing;detail="wait_callbacks_quiesced";return true;
 }
 bool quiesced(const Receipt&r,bool callbacks_drained){
  if(phase_!=Phase::quiescing||!receipt(r)||!callbacks_drained)return false;
  phase_=Phase::detaching;detail="wait_selector_registry_detach_profiles_retained";return true;
 }
 bool detached(const Receipt&r,bool old_keys_absent,bool profiles_retained,bool old_cleanup_finished){
  if(phase_!=Phase::detaching||!receipt(r)||!old_keys_absent||!profiles_retained||!old_cleanup_finished)return false;
  phase_=Phase::spawning;detail="wait_local_and_remote_planes";return true;
 }
 bool spawned(const Receipt&r,unsigned players,unsigned ai,bool duplicate_baxter,bool ids_before_register){
  if(phase_!=Phase::spawning||!receipt(r)||players!=2||ai!=2||duplicate_baxter||!ids_before_register)return false;
  phase_=Phase::loading;detail="wait_both_scene_actor_camera_initial_state";return true;
 }
 bool loaded(unsigned peer,const Receipt&r,bool scene,bool actors,bool camera,bool initial_state){
  if(phase_!=Phase::loading||peer>1||!receipt(r)||!scene||!actors||!camera||!initial_state)return false;
  loaded_|=uint8_t(1u<<peer);if(loaded_==3){phase_=Phase::flight;detail="owner_simulation_enabled";}return true;
 }
 bool stop(){
  if(phase_==Phase::idle||phase_==Phase::closed)return false;
  if(phase_==Phase::stopping)return true;
  // Invalidate every outstanding callback before the first cleanup operation.
  if(!advance_ticket())return false;
  ready_=loaded_=0;phase_=Phase::stopping;detail="wait_camera_callbacks_registry_and_object_release";return true;
 }
 bool released(const Receipt&r,bool camera,bool callbacks,bool registry,bool objects,bool queues){
  if(phase_!=Phase::stopping||!receipt(r)||!camera||!callbacks||!registry||!objects||!queues)return false;
  phase_=Phase::closed;detail="cleanup_confirmed_ids_reusable";return true;
 }
};
}
