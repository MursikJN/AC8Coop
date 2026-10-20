#include "dummy_lifecycle_core.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <initializer_list>
using namespace dummy_probe;
struct Fake {
    uintptr_t allocated = 0x10000;
    bool serial_ok = true, destroy_ok = true;
    Seen observed = Seen::safe;
    unsigned spawns = 0, serials = 0, destroys = 0, events = 0;
    void event(const char*) { ++events; }
    uintptr_t spawn() { ++spawns; return allocated; }
    bool acquire(uintptr_t p, Identity& i) { ++serials; i = {p, 42, 1001}; return serial_ok; }
    Seen inspect(const Identity&) { return observed; }
    bool destroy(uintptr_t p) { assert(p == allocated); ++destroys; return destroy_ok; }
};
int main() {
    unsigned tests = 0;
    {
        Fake b; Ledger l; l.run(b);
        assert(l.attempted && l.identified && !l.retired && b.destroys == 1);
        assert(!std::strcmp(l.status,"performed"));
        b.observed=Seen::pending; l.verify(b); assert(!l.retired && b.destroys==1);
        b.observed=Seen::retired; l.verify(b); assert(l.retired);
        l.run(b); assert(b.spawns==1); ++tests;
    }
    {
        Fake b; b.allocated=0; Ledger l; l.run(b); l.verify(b);
        assert(l.attempted && !l.identified && !l.retired && !b.serials && !b.destroys);
        l.run(b); assert(b.spawns==1); ++tests;
    }
    {
        Fake b; b.serial_ok=false; Ledger l; l.run(b); l.verify(b);
        assert(l.raw_owned==b.allocated && !l.identified && !b.destroys && !l.retired); ++tests;
    }
    for (Seen failure : {Seen::foreign, Seen::unknown, Seen::world_lost}) {
        Fake b; b.observed=failure; Ledger l; l.run(b); l.verify(b);
        assert(!b.destroys && !l.retired && l.identified); ++tests;
    }
    {
        Fake b; b.destroy_ok=false; Ledger l; l.run(b);
        for(int i=0;i<10;++i) l.verify(b);
        assert(b.destroys==3 && !l.retired && l.raw_owned); ++tests;
    }
    {
        Fake b; Ledger l; l.run(b); b.observed=Seen::foreign; l.verify(b);
        assert(b.destroys==1 && !l.retired); ++tests;
    }
    {
        Fake b; Ledger l; l.verify(b); assert(!b.spawns && !b.destroys && !l.retired); ++tests;
    }
    {
        Fake b; b.observed=Seen::retired; Ledger l; l.run(b);
        assert(l.retired && !b.destroys); ++tests;
    }
    std::printf("dummy lifecycle offline fault branches: %u passed\n",tests);
}
