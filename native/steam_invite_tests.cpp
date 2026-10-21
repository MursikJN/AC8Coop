#define AC8_STEAM_LOBBY_R24
#define AC8_SESSION_TRANSPORT
#define main original_connection_regression
#include "connection_runtime_tests.cpp"
#undef main
#define AC8_R24_BASE_INCLUDED
#define AC8_STEAM_INVITES_R25
#include "steam_lobby_bridge.cpp"
static unsigned checks25=0,dialogs25=0;
static int relationship25=3;
static bool available25=true;
static std::string sent25;
static std::vector<std::pair<ac8invite::Callback*,int>> subscriptions25;
static void verify25(bool ok){++checks25;if(!ok){fprintf(stderr,"Invite check %u failed\n",checks25);exit(1);}}
static void subscribe25(ac8invite::Callback*p,int id){p->flags|=1;p->callback_id=id;subscriptions25.push_back({p,id});}
static int relation25(void*,uint64){return relationship25;}
static bool overlay25(void*){return available25;}
static void dialog25(void*,const char*text){++dialogs25;sent25=text;}
static void write25(uint64_t request,uint64_t token){
 wchar_t path[32768]{};swprintf_s(path,L"%ls\\steam-invite-command.tsv",invites25::folder);FILE*f=nullptr;_wfopen_s(&f,path,L"wb");verify25(f!=nullptr);fprintf(f,"request\t%llu\nconfig_token\t%llu\n",request,token);fclose(f);
}
int main(){
 constexpr uint64_t host=76561198000000002ULL,self=76561198000000001ULL;uint64_t decoded=0;
 const auto text=ac8invite::encode(host);verify25(!text.empty()&&text.size()<256);
 verify25(ac8invite::decode(text.c_str(),text.size()+1,decoded)&&decoded==host);
 verify25(!ac8invite::decode(text.c_str(),text.size(),decoded));verify25(!ac8invite::decode(nullptr,256,decoded));
 std::string invalid=text;invalid[9]='2';verify25(!ac8invite::decode(invalid.c_str(),invalid.size()+1,decoded));
 invalid=text+'x';verify25(!ac8invite::decode(invalid.c_str(),invalid.size()+1,decoded));
 verify25(!ac8invite::decode("+connect 127.0.0.1",19,decoded));verify25(ac8invite::encode(0).empty());
 verify25(ac8invite::accepted(host,self,true,text.c_str(),text.size()+1,decoded));
 verify25(!ac8invite::accepted(self,self,true,text.c_str(),text.size()+1,decoded));verify25(!ac8invite::accepted(host,host,true,text.c_str(),text.size()+1,decoded));verify25(!ac8invite::accepted(host,self,false,text.c_str(),text.size()+1,decoded));
 invites25::api25.friends=reinterpret_cast<void*>(1);invites25::api25.utils=reinterpret_cast<void*>(1);invites25::api25.self=self;
 invites25::api25.relationship=relation25;invites25::api25.overlay_enabled=overlay25;invites25::api25.open_dialog=dialog25;invites25::api25.register_callback=subscribe25;
 invites25::subscribe();verify25(subscriptions25.size()==2&&subscriptions25[0].second==337&&subscriptions25[1].second==331);
 verify25(subscriptions25[0].first->GetCallbackSizeBytes()==264&&subscriptions25[1].first->GetCallbackSizeBytes()==8&&subscriptions25[0].first->callback_id==337);
 ac8invite::JoinRequested join{};join.sender=host;strcpy_s(join.connect,text.c_str());
 subscriptions25[0].first->Run(&join);invites25::consume_invites();verify25(invites25::join_sequence==1&&invites25::join_host==host);
 subscriptions25[0].first->Run(&join);invites25::consume_invites();verify25(invites25::join_sequence==1);
 subscriptions25[0].first->Run(&join,true,0);invites25::consume_invites();verify25(invites25::join_sequence==1);
 relationship25=0;invites25::last_accept=0;subscriptions25[0].first->Run(&join);invites25::consume_invites();verify25(invites25::join_sequence==1&&invites25::ignored==1);
 relationship25=3;join.sender=self;subscriptions25[0].first->Run(&join);invites25::consume_invites();verify25(invites25::join_sequence==1&&invites25::ignored==2);
 join.sender=host;for(int i=0;i<10;++i)subscriptions25[0].first->Run(&join);verify25(invites25::inbox_size==8&&invites25::overflow_count==2);invites25::consume_invites();verify25(invites25::join_sequence==2);
 ac8invite::OverlayActivated overlay{1,true,2288340};subscriptions25[1].first->Run(&overlay);verify25(invites25::overlay_active&&invites25::overlay_activations==1);
 overlay.app=1;overlay.active=0;subscriptions25[1].first->Run(&overlay);verify25(invites25::overlay_active);
 overlay.app=2288340;subscriptions25[1].first->Run(&overlay);verify25(!invites25::overlay_active);
 wchar_t current[32768]{};GetCurrentDirectoryW(32768,current);swprintf_s(invites25::folder,L"%ls\\invite-test-%lu",current,GetCurrentProcessId());verify25(CreateDirectoryW(invites25::folder,nullptr)!=0);
 lobby24::worker=CreateEventW(nullptr,TRUE,FALSE,nullptr);lobby24::configured_host=true;lobby24::config_token=123;
 write25(1,123);invites25::read_open_request();verify25(dialogs25==1&&sent25==ac8invite::encode(self));
 invites25::read_open_request();verify25(dialogs25==1);
 write25(2,122);invites25::read_open_request();verify25(dialogs25==1&&std::string(invites25::invite_state)=="ERROR_NOT_HOST_ROOM");
 lobby24::configured_host=false;write25(3,123);invites25::read_open_request();verify25(dialogs25==1);
 lobby24::configured_host=true;available25=false;write25(4,123);invites25::read_open_request();verify25(dialogs25==1&&std::string(invites25::invite_state)=="OVERLAY_UNAVAILABLE");
 available25=true;write25(5,123);invites25::read_open_request();verify25(dialogs25==2&&invites25::open_requested==2);
 invites25::publish();wchar_t status_path[32768]{};swprintf_s(status_path,L"%ls\\steam-invite-status.tsv",invites25::folder);FILE*f=nullptr;_wfopen_s(&f,status_path,L"rb");verify25(f!=nullptr);char data[2048]{};fread(data,1,sizeof(data)-1,f);fclose(f);verify25(std::strstr(data,"join_sequence\t2")&&std::strstr(data,"open_requested\t2"));
 DeleteFileW(status_path);swprintf_s(status_path,L"%ls\\steam-invite-command.tsv",invites25::folder);DeleteFileW(status_path);verify25(RemoveDirectoryW(invites25::folder)!=0);CloseHandle(lobby24::worker);lobby24::worker=nullptr;
 printf("%u Steam invite checks passed\n",checks25);
}
