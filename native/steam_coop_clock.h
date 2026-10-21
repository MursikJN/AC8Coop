#pragma once
#include <cstdint>
#include <limits>
namespace ac8coop {
// Estimate only from an echoed probe in the current authenticated connection.
// Clock values from two PCs are never compared without this calibration.
struct Clock {
 uint64_t probe=0,received=0,rtt=0;int64_t offset=0;unsigned samples=0;
 void reset(){*this={};}
 void begin(uint64_t now){probe=now;}
 bool accept(uint64_t echo,uint64_t host,uint64_t now){
  if(!probe||echo!=probe||now<echo||now-echo>200||host>uint64_t(INT64_MAX)||now>uint64_t(INT64_MAX))return false;
  const auto elapsed=now-echo;const auto next=int64_t(host)-int64_t(echo+elapsed/2);
  if(samples&&now-received<3000){
   const auto difference=next>offset?uint64_t(next)-uint64_t(offset):uint64_t(offset)-uint64_t(next);
   if(difference>(rtt+elapsed)/2+10){samples=0;}
  }
  offset=next;rtt=elapsed;received=now;probe=0;++samples;return true;
 }
 bool ready(uint64_t now)const{return samples>=2&&now>=received&&now-received<=3000&&rtt<=200;}
 uint64_t host_now(uint64_t now)const{
  if(now>uint64_t(INT64_MAX)||(offset>0&&now>uint64_t(INT64_MAX-offset)))return 0;
  const auto value=int64_t(now)+offset;return value>0?uint64_t(value):0;
 }
};
}
