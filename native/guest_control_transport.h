#pragma once
#include "guest_control_core.h"
namespace ac8input_transport {
void start();void stop();void poll();bool ready();bool host();
bool send(ac8input::Frame frame);bool take(ac8input::Frame& frame,uint64_t& received_ms);
}
