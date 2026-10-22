#include "plane_flight_state_fixture.h"
int main() {unsigned tests=0;
 {FlightFake f;Report r;assert(finalize(f,f.s,f.owned,r));assert(r.models_seeded&&r.inputs_verified&&!r.ready&&r.native_calls==5&&r.verified_scalars>100);assert(f.resets.size()==1&&f.resets[0]==f.owned.plane+0x3c60);assert(f.consumed.size()==2&&f.inputs.size()==2);++tests;}
 {FlightFake f;const auto original=f.s;plane_initial_state::put(f.s.main,0x2c,INT32_MAX);const auto before=f.s;assert(!translate(f.s,1,0,0));assert(f.s.main==before.main&&f.s.aux160==original.aux160);++tests;}
 {FlightFake f;const auto original=f.s;assert(translate(f.s,-30000,-10000,-2000));assert(plane_flight_state::value<int32_t>(f.s.main,0x2c)==3000);assert(plane_flight_state::value<int32_t>(f.s.main,0x30)==-1000);assert(f.s.aux160==original.aux160&&f.s.timestamp==original.timestamp);++tests;}
 {FlightFake f;f.set(f.owned.plane+0x2268+0x860,f.source+0xf48);Report r;assert(!finalize(f,f.s,f.owned,r)&&f.dispatches==0&&!r.ready);++tests;}
 {FlightFake f;f.set(f.owned.data[4]+8,9.0f);Report r;assert(!finalize(f,f.s,f.owned,r)&&f.dispatches==0);++tests;}
 for(unsigned i=0;i<5;++i){FlightFake f;f.fail_at=i;Report r;assert(!finalize(f,f.s,f.owned,r)&&!r.models_seeded&&!r.ready&&f.dispatches==i+1);++tests;}
 {FlightFake f;f.wrong_pose=true;Report r;assert(!finalize(f,f.s,f.owned,r)&&!r.models_seeded&&!r.ready);++tests;}
 {FlightFake f;f.wrong_input=true;Report r;assert(!finalize(f,f.s,f.owned,r)&&f.dispatches==4&&!r.ready);++tests;}
 {FlightFake f;auto m=f.owned.plane+0x2268;f.set(m+0x8b0,uint32_t{1<<24});f.set(m+0xd8,0.5f);f.set(m+0x68,1.0f);std::array<float,6> out;assert(expected_input(f,m,f.s,out));assert(out[0]==0.125f&&out[3]==1.0f);++tests;}
 {FlightFake f;auto m=f.owned.plane+0x2268;f.set(m+0x8b0,uint32_t{1<<19});f.set(m+0xdd,uint8_t{1});std::array<float,6> out;assert(expected_input(f,m,f.s,out)&&out[3]==1&&out[4]==0);++tests;}
 {FlightFake f;f.set(f.image+0xdc4c03c,99.0f);Report r;assert(!finalize(f,f.s,f.owned,r)&&f.dispatches==0);++tests;}
 {FlightFake f;Report r;assert(finalize(f,f.s,f.owned,r));auto m=f.owned.plane+0x2268;
   plane_initial_state::put(f.s.aux140,8,2.0f);plane_initial_state::put(f.s.aux140,0xc,-3.0f);plane_initial_state::put(f.s.aux140,0x10,5.0f);
   plane_initial_state::put(f.s.aux140,0x34,uint8_t{0xdd});f.set(m+0x128,3.0);f.set(m+0x130,5.0);f.set(m+0x138,2.0);f.set(m+0x124,uint8_t{1});f.set(m+0x125,uint8_t{5});f.set(m+0x126,uint8_t{11});
   plane_initial_state::put(f.s.aux150,0x14,7.0f);plane_initial_state::put(f.s.aux150,0x18,-11.0f);plane_initial_state::put(f.s.aux150,0x1c,13.0f);
   f.set(m+0x38,11.0);f.set(m+0x40,13.0);f.set(m+0x48,7.0);
   assert(verify_model(f,m,f.s,r));f.set(m+0x126,uint8_t{10});assert(!verify_model(f,m,f.s,r));++tests;}
 std::printf("plane flight state: %u tests passed; offline contracts only, no native execution\n",tests);return 0;
}
