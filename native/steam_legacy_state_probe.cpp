// Read-only diagnostic for the game's existing legacy Steam P2P session.
// No Steam initialization, callback pumping, accepting, sending or closing sessions.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <cstddef>
struct P2PState {
 uint8_t active,connecting,error,relay;
 int32_t queued_bytes,queued_packets;
 uint32_t remote_ip;
 uint16_t remote_port;
};
static_assert(sizeof(P2PState)==20 && offsetof(P2PState,remote_port)==16,"Steam P2P state ABI");
template<class T>static T api(HMODULE m,const char*n){return reinterpret_cast<T>(GetProcAddress(m,n));}
static bool env(const wchar_t*n,wchar_t*b,DWORD capacity){auto v=GetEnvironmentVariableW(n,b,capacity);return v>0&&v<capacity;}
static const char* inspect(FILE*f,uint64_t peer){
 HMODULE m=GetModuleHandleW(L"steam_api64.dll");if(!m)return "steam_module_absent";
 auto user_handle=api<int(__cdecl*)()>(m,"SteamAPI_GetHSteamUser");
 auto user_get=api<void*(__cdecl*)()>(m,"SteamAPI_SteamUser_v021");
 auto utils_get=api<void*(__cdecl*)()>(m,"SteamAPI_SteamUtils_v010");
 auto app=api<uint32_t(__cdecl*)(void*)>(m,"SteamAPI_ISteamUtils_GetAppID");
 auto online=api<bool(__cdecl*)(void*)>(m,"SteamAPI_ISteamUser_BLoggedOn");
 auto self=api<uint64_t(__cdecl*)(void*)>(m,"SteamAPI_ISteamUser_GetSteamID");
 auto networking=api<void*(__cdecl*)()>(m,"SteamAPI_SteamNetworking_v006");
 auto state=api<bool(__cdecl*)(void*,uint64_t,P2PState*)>(m,"SteamAPI_ISteamNetworking_GetP2PSessionState");
 if(!user_handle||!user_get||!utils_get||!app||!online||!self||!networking||!state)return "export_absent";
 if(user_handle()<=0)return "steam_context_absent";
 void* u=user_get();void* utils=utils_get();
 if(!u||!utils||app(utils)!=2288340||!online(u))return "steam_context_not_ready";
 auto id=self(u);fprintf(f,"self\t%llu\npeer\t%llu\n",static_cast<unsigned long long>(id),static_cast<unsigned long long>(peer));
 if(!id||peer==id)return "invalid_peer";
 void* net=networking();if(!net)return "legacy_interface_absent";
 P2PState value{};bool present=state(net,peer,&value);
 fprintf(f,"session_exists\t%d\nactive\t%u\nconnecting\t%u\np2p_error\t%u\nrelay\t%u\nqueued_bytes\t%d\nqueued_packets\t%d\n",present?1:0,value.active,value.connecting,value.error,value.relay,value.queued_bytes,value.queued_packets);
 return present?"session_state_observed":"no_session_for_peer";
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_legacy_state(void*){
 wchar_t marker[8]{},directory[32768]{},path[32768]{},exe[32768]{};
 if(!env(L"AC8_COOP_RECON",marker,8)||wcscmp(marker,L"1")||!env(L"AC8_COOP_RECON_OUTPUT",directory,32768))return 0;
 auto n=GetModuleFileNameW(nullptr,exe,32768);auto base=wcsrchr(exe,L'\\');
 if(!n||n>=32768||!base||_wcsicmp(base+1,L"AceCombat8.exe"))return 0;
 if(swprintf_s(path,L"%ls\\native-steam-peer.txt",directory)<0)return 0;
 FILE*in=nullptr;if(_wfopen_s(&in,path,L"rb")||!in)return 0;
 char text[20]{};size_t length=fread(text,1,sizeof(text),in);fclose(in);
 if(length!=17||memcmp(text,"7656119",7))return 0;
 uint64_t peer=0;for(size_t i=0;i<length;++i){if(text[i]<'0'||text[i]>'9')return 0;peer=peer*10+static_cast<unsigned>(text[i]-'0');}
 if(swprintf_s(path,L"%ls\\native-steam-state.tsv",directory)<0)return 0;
 FILE*f=nullptr;if(_wfopen_s(&f,path,L"w")||!f)return 0;
 fprintf(f,"observed_tick_ms\t%llu\n",GetTickCount64());
 __try{fprintf(f,"status\t%s\n",inspect(f,peer));}__except(EXCEPTION_EXECUTE_HANDLER){fprintf(f,"status\tnative_read_fault\n");}
 fclose(f);return 0;
}
