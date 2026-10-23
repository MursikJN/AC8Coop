#pragma once
#include <cstdint>
namespace ac8owner {
// Capture identity before any slow asset load/start attempt. Never retarget a
// receipt: teardown must refer to the exact original camera, including serial.
template<class B,class Id>bool track_camera(B&b,Id&receipt,uintptr_t pointer){
 if(!b.game_thread()||!pointer)return false;
 if(receipt.p)return receipt.p==pointer&&b.same_id(receipt);
 Id candidate{};if(!b.camera_identity(pointer,candidate))return false;
 receipt=candidate;return true;
}
inline bool needs_owner_cleanup(bool host,bool camera_tracked){return !host||camera_tracked;}
}
