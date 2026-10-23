#pragma once
#include <cstdint>
namespace ac8owner {
enum class IdentityKind { instance, cdo };
// Same dead-object mask as the existing exact-build identity gate. CDO is
// an explicit separate kind, never a relaxation of the instance predicate.
inline bool identity_flags(uint32_t flags,IdentityKind kind){
 return !(flags&0x60000000)&&((flags&0x10)!=0)==(kind==IdentityKind::cdo);
}
// Existing build25201480 class/CDO links and F-14D vtable (R19 evidence).
template<class B,class Id>bool template_identity(const B&b,const Id&klass,const Id&cdo,uintptr_t expected_vtable){
 if(!b.same_id(klass)||!b.same_cdo_id(cdo)||klass.p==cdo.p)return false;
 uintptr_t p=0;uint32_t flags=0;
 if(!b.read(klass.p+0x110,p)||p!=cdo.p||!b.read(cdo.p+0x10,p)||p!=klass.p||
    !b.read(cdo.p,p)||p!=expected_vtable||!b.read(cdo.p+8,flags)||!identity_flags(flags,IdentityKind::cdo))return false;
 return b.same_id(klass)&&b.same_cdo_id(cdo);
}
}
