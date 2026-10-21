#pragma once
#include <cstdint>
namespace ac8cinema {
struct Gate {
 uint32_t scene=0;bool voting=false,requested=false,authorized=false,consumed=false;
 bool configure(uint32_t next,bool enabled,bool permit){
  if(!next||next<scene)return false;
  if(next!=scene){scene=next;requested=authorized=consumed=false;}
  voting=enabled;if(permit)authorized=true;return true;
 }
 bool decide(bool stock_complete){
  if(voting&&stock_complete)requested=true;
  if(!authorized||consumed)return false;
  consumed=true;return true;
 }
};
}
