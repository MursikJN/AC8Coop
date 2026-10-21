#pragma once
#include "plane_coop_protocol.h"
namespace ac8flight_transport {
void start();void stop();void poll();bool ready();bool host();
bool send(ac8flight::Frame frame,bool reliable);bool take(ac8flight::Frame& frame);
}
