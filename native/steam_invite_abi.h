#pragma once
#include <cstdint>
// Windows x64 contract checked against Valve Proton steamworks_sdk_157:
// steam_api_common.h CCallbackBase, isteamfriends.h callbacks 331 and 337.
// No virtual destructor: the three SDK vtable entries must retain their order.
namespace ac8invite {
class Callback {
public:
 virtual void Run(void*)=0;
 virtual void Run(void*,bool,uint64_t)=0;
 virtual int GetCallbackSizeBytes()=0;
 uint8_t flags=0;
 int callback_id=0;
};
struct JoinRequested {uint64_t sender;char connect[256];};
struct OverlayActivated {uint8_t active;bool user_initiated;uint32_t app;};
static_assert(sizeof(Callback)==16,"Steam x64 callback base changed");
static_assert(sizeof(JoinRequested)==264,"Steam callback 337 changed");
static_assert(sizeof(OverlayActivated)==8,"Steam callback 331 changed");
}
