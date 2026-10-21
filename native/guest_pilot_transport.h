#pragma once
#include "guest_pilot_protocol.h"
namespace ac8pilot_transport {
void start();void stop();void poll();bool ready();ac8pilot::Context context();
bool send(ac8pilot::Frame);bool take(ac8pilot::Frame&,uint64_t&);
}
