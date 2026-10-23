#pragma once
#include <cstddef>
namespace ac8adapter {
inline constexpr char pause_update_fingerprint[]="40574883ec2080793800488bf90f849b";
static_assert(sizeof(pause_update_fingerprint)==33,"A 16-byte fingerprint must have exactly 32 hex digits");
inline constexpr char pause_reason_shift_fingerprint[]="8b49288bc1c1e80548895c2430894f2c";
inline constexpr char pause_override_branch_fingerprint[]="a801750a837f3400740432dbeb0585c9";
static_assert(sizeof(pause_reason_shift_fingerprint)==33&&sizeof(pause_override_branch_fingerprint)==33);
inline constexpr unsigned pause_protocol=2;
}
