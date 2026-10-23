#pragma once
#include "owner_template_identity.h"
namespace ac8owner {
template<class B,class Id>bool capture_identity(B&b,uintptr_t p,Id&out,bool mint,IdentityKind kind,const char*&why){
 int32_t index=-1,serial=0;uint32_t flags=0;uintptr_t at=0,actual=0;
 auto fail=[&](const char*s){why=s;return false;};
 if(p<0x10000||p>=0x800000000000ULL)return fail("pointer_range");
 if(!b.read(p+12,index))return fail("index_read");
 if(!b.slot(index,at))return fail("slot_lookup");
 if(!b.read(at,actual)||actual!=p)return fail("slot_pointer");
 if(!b.read(p+8,flags))return fail("flags_read");
 if(!identity_flags(flags,kind))return fail("object_flags");
 if(!b.read(at+16,serial))return fail("serial_read");
 if(!serial&&mint){const auto assigned=b.mint(index);if(!b.read(at+16,serial)||serial!=assigned)return fail("serial_mint_readback");}
 if(serial<=0)return fail("serial_unassigned");
 int32_t index_after=-1,serial_after=0;uintptr_t at_after=0;
 if(!b.read(p+12,index_after)||index_after!=index||!b.slot(index,at_after)||at_after!=at||
    !b.read(at,actual)||actual!=p||!b.read(at+16,serial_after)||serial_after!=serial||
    !b.read(p+8,flags)||!identity_flags(flags,kind))return fail("identity_changed");
 out={p,index,serial};why="ok";return true;
}
}
