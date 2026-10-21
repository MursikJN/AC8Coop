#include "steam_legacy_host_bridge.cpp"
#include <cassert>
static int accepted_count=0;
static bool __cdecl accepted(void*,uint64_t peer){assert(peer==allowed_peer);++accepted_count;return true;}
int main(){
 enabled=true;allowed_peer=76561198000000001ull;accept_peer=accepted;
 request_callback.Run(&allowed_peer);assert(accepted_count==0);drain();assert(accepted_count==1);
 uint64_t unrelated=76561198000000002ull;request_callback.Run(&unrelated);drain();assert(accepted_count==1);
 enabled=false;request_callback.Run(&allowed_peer);drain();assert(accepted_count==1);
 enabled=true;for(int i=0;i<129;++i)request_callback.Run(&allowed_peer);drain();assert(accepted_count==1);
 Event error{allowed_peer,2,4};enqueue(error);drain();assert(accepted_count==1);
 request_callback.Run(nullptr);drain();assert(accepted_count==1);
 puts("6 legacy host callback guard checks passed");
}
