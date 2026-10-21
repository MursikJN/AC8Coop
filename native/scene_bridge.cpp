#define AC8_SCENE_TRANSPORT
#include "connection_test.cpp"
#include <string>
#include <ctime>
namespace scene_bridge {
static std::wstring directory;static uint64_t published=0;static bool running=false,as_host=false;static DWORD owner=0;
bool setup(){
 wchar_t marker[32]{},folder[32768]{},current_role[16]{},exe[32768]{};
 if(!GetEnvironmentVariableW(L"AC8_SCENE_STEAM",marker,32)||wcscmp(marker,L"25201480")||
    !GetEnvironmentVariableW(L"AC8_COOP_RECON_OUTPUT",folder,32768)||!GetEnvironmentVariableW(L"AC8_CONNECTION_ROLE",current_role,16))return false;
 if(wcscmp(current_role,L"host")&&wcscmp(current_role,L"guest"))return false;
 if(!GetModuleFileNameW(nullptr,exe,32768))return false;auto file=wcsrchr(exe,L'\\');if(!file||_wcsicmp(file+1,L"AceCombat8.exe"))return false;
 if(!owner)owner=GetCurrentThreadId();if(owner!=GetCurrentThreadId())return false;
 directory=folder;as_host=!wcscmp(current_role,L"host");return true;
}
bool read_snapshot(std::string&payload,uint64_t&generation,uint64_t&sequence){
 auto path=directory+L"\\scene-host.ac8w";FILE*f=_wfsopen(path.c_str(),L"rb",_SH_DENYNO);if(!f)return false;
 payload.resize(ac8scene::max_bytes+1);auto n=fread(payload.data(),1,payload.size(),f);fclose(f);payload.resize(n);
 constexpr char prefix[]="AC8W\t1\t25201480\nframe\t";
 constexpr char visual_prefix[]="AC8W\t2\t25201480\nframe\t";
 if(n<40||n>ac8scene::max_bytes||payload.back()!='\n'||(payload.compare(0,sizeof(prefix)-1,prefix)&&payload.compare(0,sizeof(visual_prefix)-1,visual_prefix)))return false;
 unsigned long long seq=0,gen=0;unsigned revision=0;double stamp=0;
 if(sscanf_s(payload.c_str()+sizeof(prefix)-1,"%llu\t%llu\t%u\t%lf",&seq,&gen,&revision,&stamp)!=4||!seq||!gen||!revision)return false;
 // The Lua codec validates data before publication and on receipt. This layer
 // guarantees bounded framing and identity, and never evaluates the payload.
 generation=gen;sequence=seq;return true;
}
void start(){if(!setup()||running)return;ac8scene_transport::start();published=0;running=true;}
void tick(){
 if(!setup()||!running)return;ac8scene_transport::poll();if(!ac8scene_transport::ready())return;
 if(as_host){std::string payload;uint64_t generation=0,sequence=0;if(read_snapshot(payload,generation,sequence)&&sequence>published&&ac8scene_transport::send(payload,generation,sequence))published=sequence;}
 else{std::string payload;while(ac8scene_transport::take(payload)){
  auto temporary=directory+L"\\scene-client.ac8w.tmp",path=directory+L"\\scene-client.ac8w";FILE*f=nullptr;
  if(!_wfopen_s(&f,temporary.c_str(),L"wb")&&f){auto n=fwrite(payload.data(),1,payload.size(),f);fclose(f);if(n==payload.size())MoveFileExW(temporary.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING);}
 }}
}
void stop(){if(!setup())return;ac8scene_transport::stop();running=false;}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_scene_start(void*){scene_bridge::start();return 0;}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_scene_tick(void*){scene_bridge::tick();return 0;}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_scene_stop(void*){scene_bridge::stop();return 0;}
