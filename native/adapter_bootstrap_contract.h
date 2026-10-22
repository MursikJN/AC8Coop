#pragma once
#include <cstddef>
namespace ac8adapter {
inline constexpr char pause_update_fingerprint[]="40574883ec2080793800488bf90f849b";
static_assert(sizeof(pause_update_fingerprint)==33,"A 16-byte fingerprint must have exactly 32 hex digits");
inline constexpr unsigned pause_protocol=2;
}
