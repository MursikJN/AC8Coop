#define AC8_GUEST_INPUT_TRANSPORT
#include "connection_test.cpp"
// Native game adapter ABI; all functions must be called on the transport owner thread.
// This DLL alone does not read controls, replace a wingman, or render the guest world.
extern "C" __declspec(dllexport) int __cdecl ac8_guest_input_submit(
 uint64_t generation,uint32_t revision,uint32_t slot,int16_t pitch,int16_t roll,int16_t yaw,int16_t throttle,int16_t brake){
 ac8input::Frame f;f.generation=generation;f.revision=revision;f.slot=slot;f.aircraft=23;f.axes={pitch,roll,yaw,throttle,brake};
 return ac8input_transport::send(f)?1:0;
}
extern "C" __declspec(dllexport) int __cdecl ac8_guest_input_take(void* encoded,size_t capacity,uint64_t* received_ms){
 if(!encoded||capacity!=ac8input::packet_size||!received_ms)return 0;
 ac8input::Frame f;uint64_t at=0;if(!ac8input_transport::take(f,at))return 0;
 const auto bytes=ac8input::encode(f);memcpy(encoded,bytes.data(),bytes.size());*received_ms=at;return 1;
}
