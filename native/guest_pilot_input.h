#pragma once
#include <array>
#include <algorithm>
#include <cstdint>
#include <cmath>
namespace ac8pilot {
struct RawInput{
 bool focused=false,up=false,down=false,left=false,right=false,yaw_left=false,yaw_right=false,throttle=false,brake=false;
 bool pad_left=false,pad_right=false;int16_t stick_x=0,stick_y=0;uint8_t trigger_left=0,trigger_right=0;
};
inline float stick(int16_t n){constexpr int deadzone=7849;int value=n;int magnitude=std::abs(value);if(magnitude<=deadzone)return 0;
 return std::clamp(float(magnitude-deadzone)/float(32767-deadzone),0.f,1.f)*(value<0?-1.f:1.f);
}
inline std::array<int16_t,5> axes(const RawInput&r){
 std::array<int16_t,5>out{};if(!r.focused)return out;
 auto signed_axis=[](float x){return int16_t(std::lround(std::clamp(x,-1.f,1.f)*32767));};
 auto trigger=[](uint8_t x){return x<=30?0.f:float(x-30)/225.f;};
 out[0]=signed_axis(float(r.up)-float(r.down)+stick(r.stick_y));
 out[1]=signed_axis(float(r.right)-float(r.left)+stick(r.stick_x));
 out[2]=signed_axis(float(r.yaw_right||r.pad_right)-float(r.yaw_left||r.pad_left));
 out[3]=signed_axis(std::max(float(r.throttle),trigger(r.trigger_right)));
 out[4]=signed_axis(std::max(float(r.brake),trigger(r.trigger_left)));return out;
}
}
