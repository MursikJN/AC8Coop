#include "connection_protocol.h"
#include <cassert>
#include <cstdio>
using namespace ac8test;
int main() {
    Session h,g;h.reset(Role::host,1,2,101);g.reset(Role::guest,2,1,202);
    Packet out{}; auto hg=h.make(Kind::hello),gg=g.make(Kind::hello);
    auto bytes=encode(hg); assert(decode(bytes.data(),bytes.size(),out));assert(out.nonce==101);
    assert(!decode(bytes.data(),47,out));assert(!decode(nullptr,48,out));
    auto bad=bytes;bad[4]=2;assert(!decode(bad.data(),48,out));
    bad=bytes;bad[8]^=1;assert(!decode(bad.data(),48,out));
    bad=bytes;bad[6]=99;assert(!decode(bad.data(),48,out));
    Packet foreign=gg;foreign.sender=3;assert(!h.accept(foreign));
    foreign=gg;foreign.role=Role::host;assert(!h.accept(foreign));
    auto early=g.make(Kind::ping);assert(!h.accept(early));
    assert(h.accept(gg));assert(g.accept(hg));assert(!h.ready() && !g.ready());
    auto ha=h.make(Kind::ack),ga=g.make(Kind::ack);
    assert(h.accept(ga));assert(g.accept(ha));assert(h.ready() && g.ready());
    assert(!h.accept(ga)); // duplicated sequence
    auto ping=h.make(Kind::ping,1234);assert(g.accept(ping));
    auto pong=g.make(Kind::pong,ping.timestamp);assert(h.accept(pong));assert(pong.timestamp==1234);
    auto stale=g.make(Kind::ping);stale.nonce=999;assert(!h.accept(stale));
    stale=g.make(Kind::ping);stale.echo=999;assert(!h.accept(stale));
    auto oldhello=gg;h.reset(Role::host,1,2,303);
    assert(!h.ready());assert(!h.accept(pong)); // old ACK/data cannot validate new connection
    g.reset(Role::guest,2,1,404);assert(g.accept(h.make(Kind::hello)));assert(h.accept(g.make(Kind::hello)));
    assert(g.accept(h.make(Kind::ack)));assert(h.accept(g.make(Kind::ack)));assert(h.ready() && g.ready());
    oldhello.sequence=999;assert(!h.accept(oldhello)); // changed remote generation on active connection
    assert(g.accept(h.make(Kind::bye)));
    puts("Protocol tests passed: encoding, bounds, identity/role, handshake, replay, epochs, rejoin, goodbye.");
}
