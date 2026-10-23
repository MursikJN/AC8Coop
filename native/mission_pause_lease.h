#pragma once
#include <cstdint>
namespace ac8pause {
// SafeMode is the same pause reason used by the stock dialog stack.
template<uint32_t Reason> struct ReasonLease {
 static constexpr uint32_t bit=Reason;
 bool held=false;
 bool acquire(uint32_t& flags) {
  if(!held && (flags&bit))return false;
  held=true;flags|=bit;return true;
 }
 void release(uint32_t& flags) {if(held)flags&=~bit;held=false;}
};
using Lease=ReasonLease<8>;
// Exact build Update at RVA 0x79163f0 tests bit 5 before override +0x34.
// For the disconnect lab only: stock override-resistant reason, counter untouched.
using DisconnectLease=ReasonLease<32>;
}
