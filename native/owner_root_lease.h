#pragma once
namespace ac8owner {
// Never clear a root owned by the engine/another mod, or touch a reused slot.
template<class Id>struct RootLease {
 Id id{};bool captured=false,owned=false;
 template<class B>bool acquire(B&b,const Id&next){
  if(captured)return id.p==next.p&&id.index==next.index&&id.serial==next.serial&&b.live(id)&&b.rooted(id);
  if(!b.live(next))return false;
  id=next;captured=true;owned=!b.rooted(id);
  if(owned)b.set_root(id);
  return b.live(id)&&b.rooted(id);
 }
 template<class B>bool release(B&b){
  if(!captured)return true;
  if(!b.live(id))return false;
  if(owned){if(!b.rooted(id))return false;b.clear_root(id);if(b.rooted(id))return false;}
  captured=false;owned=false;id={};return true;
 }
};
}
