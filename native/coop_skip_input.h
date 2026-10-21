#pragma once
#include <cstdint>
namespace ac8coop {
struct SkipHold {
 bool armed=false,started=false,voted=false;uint64_t since=0;uint32_t scene=0;
 bool sample(uint64_t now,bool focused,bool down,uint32_t phase,uint32_t current_scene){
  if(!down){*this={};armed=true;return false;}
  if(!focused||phase!=2||!current_scene){armed=false;started=false;return false;}
  if(!armed)return false;
  if(!started){started=true;since=now;scene=current_scene;}
  if(current_scene!=scene||now<since){armed=false;return false;}
  if(!voted&&now-since>=700){voted=true;return true;}return false;
 }
};
}
