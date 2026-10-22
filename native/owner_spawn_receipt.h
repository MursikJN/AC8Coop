#pragma once
#include <cstdint>
#ifdef _MSC_VER
#define AC8_RECEIPT_ABI __fastcall
#else
#define AC8_RECEIPT_ABI
#endif
namespace ac8owner {
// Matches the already verified R19 dispatcher: storage -> context; invoke is
// handed context and a pointer to a temporary actor pointer, not storage/actor.
template<class B,class L>struct SpawnReceipt {
 struct Context{B*backend;L*ledger;};
 struct Storage{uintptr_t*table;Context*context;};
 static void*AC8_RECEIPT_ABI address(void*p){return static_cast<Storage*>(p)->context;}
 static void AC8_RECEIPT_ABI invoke(void*p,uintptr_t*actor){auto*c=static_cast<Context*>(p);c->ledger->receipt(*c->backend,actor?*actor:0);}
};
}
#undef AC8_RECEIPT_ABI
