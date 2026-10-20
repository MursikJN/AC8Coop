#pragma once
#include <array>
#include <cstdint>
#include <cstring>

namespace ac8test {
constexpr uint32_t build = 25201480;
constexpr size_t packet_size = 48;
enum class Kind : uint8_t { hello=1, ack=2, ping=3, pong=4, bye=5 };
enum class Role : uint8_t { host=1, guest=2 };
struct Packet {
    Kind kind{}; Role role{}; uint32_t sequence{};
    uint64_t sender{}, nonce{}, echo{}, timestamp{};
};
inline void put(uint8_t* p, uint64_t v, size_t count) {
    for (size_t i=0;i<count;++i) p[i]=static_cast<uint8_t>(v >> (8*i));
}
inline uint64_t get(const uint8_t* p, size_t count) {
    uint64_t v=0; for(size_t i=0;i<count;++i) v|=uint64_t(p[i]) << (8*i); return v;
}
inline std::array<uint8_t,packet_size> encode(const Packet& p) {
    std::array<uint8_t,packet_size> b{};
    memcpy(b.data(),"AC8T",4); put(b.data()+4,1,2);
    b[6]=static_cast<uint8_t>(p.kind); b[7]=static_cast<uint8_t>(p.role);
    put(b.data()+8,build,4); put(b.data()+12,p.sequence,4);
    put(b.data()+16,p.sender,8); put(b.data()+24,p.nonce,8);
    put(b.data()+32,p.echo,8); put(b.data()+40,p.timestamp,8);
    return b;
}
inline bool decode(const void* data, size_t size, Packet& p) {
    if (!data || size!=packet_size) return false;
    const auto* b=static_cast<const uint8_t*>(data);
    if(memcmp(b,"AC8T",4) || get(b+4,2)!=1 || get(b+8,4)!=build ||
       b[6]<1 || b[6]>5 || b[7]<1 || b[7]>2) return false;
    p={static_cast<Kind>(b[6]),static_cast<Role>(b[7]),static_cast<uint32_t>(get(b+12,4)),
       get(b+16,8),get(b+24,8),get(b+32,8),get(b+40,8)};
    return true;
}
struct Session {
    Role role{}; uint64_t local{}, peer{}, nonce{}, remote{};
    uint32_t tx{}, rx{}; bool hello_received{}, ack_received{};
    void reset(Role r,uint64_t l,uint64_t p,uint64_t fresh) {
        *this={};role=r;local=l;peer=p;nonce=fresh;
    }
    bool ready() const { return hello_received && ack_received; }
    Packet make(Kind kind,uint64_t stamp=0) {
        return {kind,role,++tx,local,nonce,remote,stamp};
    }
    // Transport sender, role, protocol/build, generation and replay checks are independent.
    bool accept(const Packet& p) {
        if(!nonce || !peer || p.sender!=peer || p.role==role || !p.nonce || p.sequence<=rx) return false;
        if(p.kind==Kind::hello) {
            if((remote && p.nonce!=remote) || (p.echo && p.echo!=nonce)) return false;
            remote=p.nonce;hello_received=true;
        } else {
            if(!hello_received || p.nonce!=remote || p.echo!=nonce) return false;
            if(p.kind==Kind::ack) ack_received=true;
            else if(!ready()) return false;
        }
        rx=p.sequence;return true;
    }
};
} // namespace ac8test
