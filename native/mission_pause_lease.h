#pragma once
#include <cstdint>
namespace ac8pause {
// SafeMode is the same pause reason used by the stock dialog stack.
struct Lease {
 static constexpr uint32_t bit=8;
 bool held=false;
 bool acquire(uint32_t& flags) {
  if(!held && (flags&bit))return false;
  held=true;flags|=bit;return true;
 }
 void release(uint32_t& flags) {if(held)flags&=~bit;held=false;}
};
}
