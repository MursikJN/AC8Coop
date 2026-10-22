#define AC8_STEAM_COOP_R27
#define AC8_MISSION_SYNC_R26
#define AC8_STEAM_LOBBY_R24
#define AC8_STEAM_INVITES_R25
#define AC8_SESSION_TRANSPORT
#define AC8_GUEST_PILOT_TRANSPORT
#define AC8_SCENE_TRANSPORT
#include "connection_test.cpp"
#include "steam_coop_channels.inl"
#define AC8_R24_BASE_INCLUDED
#include "steam_lobby_bridge.cpp"
#ifdef AC8_OWNER_NATIVE_R31
#include "steam_shutdown.inl"
#endif
#define AC8_R27_EMBEDDED_PILOT
#ifdef AC8_OWNER_NATIVE_R31
#define AC8_PILOT_REV r31
#elif defined(AC8_OWNER_SIM_R30)
#define AC8_PILOT_REV r30
#elif defined(AC8_SESSION_POLICY_R29)
#define AC8_PILOT_REV r29
#elif defined(AC8_CINEMA_SYNC_R28)
#define AC8_PILOT_REV r28
#else
#define AC8_PILOT_REV r27
#endif
#include "guest_pilot_bridge.cpp"
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_coop27_capture_vote(void*){coop27::capture_vote();return 0;}
