#pragma once
#include <array>
#include <cstdint>
namespace plane_flight_cadence {
constexpr unsigned max_samples=4096;
struct StatusGate {
 uint64_t last_ms=0;bool initialized=false;
 bool publish(uint64_t now,bool frequent_active){
  if(!frequent_active||!initialized||now<last_ms||now-last_ms>=1000){last_ms=now;initialized=true;return true;}
  return false;
 }
};
inline bool delta(uint64_t previous,uint64_t current,float& dt,bool& clamped){
 dt=0;clamped=false;if(!previous||current<=previous)return false;
 const uint64_t us=current-previous;clamped=us>100000;
 dt=static_cast<float>(clamped?100000:us)/1000000.f;return true;
}
struct Sample {
 uint64_t begin_us=0,interval_us=0,state_us=0,model_us=0,pose_us=0,total_us=0,source_timestamp=0;
 float dt=0;bool dt_clamped=false,moved=false,actual_valid=false,success=false;
 std::array<double,3> requested{},rotation{},actual{};
};
struct Trace {
 std::array<Sample,max_samples> samples{};unsigned count=0,dropped=0;bool emitted=false;
 void append(const Sample& sample){if(count<max_samples)samples[count++]=sample;else ++dropped;}
};
}
