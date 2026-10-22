// Called on the game thread before QuitGame, never from DllMain. No SteamAPI_Shutdown.
namespace shutdown31 {
static bool requested=false,failed=false;
static void publish(){
 wchar_t folder[32768]{},path[32768]{},temp[32768]{};
 if(!read_env(L"AC8_COOP_RECON_OUTPUT",folder,32768))return;
 swprintf_s(path,L"%ls\\native-shutdown.tsv",folder);swprintf_s(temp,L"%ls.tmp",path);
 const bool running=lobby24::worker&&WaitForSingleObject(lobby24::worker,0)!=WAIT_OBJECT_0;
 const bool complete=requested&&!failed&&!running&&!invites25::registered;
 FILE*f=_wfsopen(temp,L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"format\tac8-native-shutdown-v1\nconfig_token\t%llu\nrequested\t%d\nworker_running\t%d\ncallbacks_registered\t%d\ncomplete\t%d\nfailed\t%d\n",lobby24::config_token,requested?1:0,running?1:0,invites25::registered?1:0,complete?1:0,failed?1:0);
 fclose(f);MoveFileExW(temp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
static void step(bool begin){
 if(begin&&!requested){requested=true;lobby24::stopping=true;invites25::shutdown();if(!invites25::retired)failed=true;}
 publish();
}
static int boundary(bool begin){
 __try{step(begin);}__except(EXCEPTION_EXECUTE_HANDLER){failed=true;publish();}
 return 0;
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_shutdown_begin(void*){return shutdown31::boundary(true);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_shutdown_poll(void*){return shutdown31::boundary(false);}
