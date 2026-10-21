#pragma once
#include "scene_protocol.h"
namespace ac8scene_transport {
void start();void stop();void poll();bool ready();
bool send(const std::string&payload,uint64_t generation,uint64_t transfer);
bool take(std::string&payload);
}
