// Protocol-only loopback peer for one real guest game. No game model, DLL
// injection or Steam connection. The live test seed comes from the lab Pawn.
#define AC8_OWNER_SIM_R30
#define NOMINMAX
#include "guest_pilot_loopback.h"
#include <fstream>
#include <map>
#include <string>
#include <cwchar>
int wmain(int argc,wchar_t**argv){
 if(argc==3&&!wcscmp(argv[1],L"--wire-fixture")){
  ac8pilot::Frame f;f.kind=ac8pilot::Kind::owner_state;f.sender=2;f.session=20;f.echo=10;f.sequence=1;f.generation=7;f.source_us=1000000;f.count=1;
  auto&p=f.poses[0];p.role=1;p.aircraft=23;p.position={100,200,300};p.rotation={0,0,0,1};p.speed=100;f.velocity={101,202,303};
  const auto b=ac8pilot::encode(f);std::ofstream file(argv[2],std::ios::binary);file.write(reinterpret_cast<const char*>(b.data()),b.size());return file?0:5;
 }
 if(argc!=3)return 2;const std::wstring directory=argv[1];wchar_t*end=nullptr;const auto token=wcstoull(argv[2],&end,10);if(!token||*end)return 2;
 ac8pilot::Loopback loop;if(!loop.open(true,0,token))return 3;
 {std::ofstream out(directory+L"\\owner-lab-peer.tsv");out<<"port\t"<<loop.port<<"\ntoken\t"<<token<<"\n";}
 ac8pilot::Frame baseline;bool seeded=false,loaded=false,stop=false;uint64_t owners=0,last_send=0,last_report=0;const auto start=GetTickCount64();
 while(!stop&&GetTickCount64()-start<1800000){
  if(!loop.poll([&](const ac8pilot::Frame&f,uint64_t){if(f.kind==ac8pilot::Kind::loaded)loaded=true;else if(f.kind==ac8pilot::Kind::owner_state){++owners;baseline.poses[1]=f.poses[0];baseline.poses[1].health=baseline.poses[1].max_health=100;}else if(f.kind==ac8pilot::Kind::stop)stop=true;}))break;
  if(!seeded){
   std::ifstream file(directory+L"\\owner-lab-host-seed.tsv");std::map<std::string,double>v;std::string key;double value=0;while(file>>key>>value)v[key]=value;
   if(v.size()==8&&v.count("x")&&v.count("y")&&v.count("z")&&v.count("qx")&&v.count("qy")&&v.count("qz")&&v.count("qw")&&v.count("speed")){
    baseline.sender=1;baseline.session=baseline.echo=token;baseline.sequence=1;baseline.generation=1;baseline.revision=1;baseline.flags=ac8pilot::flight_only;baseline.count=4;baseline.source_us=1;
    for(unsigned i=0;i<4;++i){auto&p=baseline.poses[i];p.role=i;p.aircraft=23;p.position={v["x"],v["y"],v["z"]};p.rotation={float(v["qx"]),float(v["qy"]),float(v["qz"]),float(v["qw"])};p.speed=float(v["speed"]);p.health=p.max_health=100;}
    if(!ac8pilot::valid(baseline))return 4;seeded=true;
   }
  }
  const auto now=GetTickCount64();
  if(seeded&&loop.connected&&now-last_send>=33){baseline.flags=ac8pilot::flight_only|(loaded?ac8pilot::loaded_ack:0);baseline.source_us=now*1000;if(loop.send_frame(baseline))last_send=now;}
  if(now-last_report>=1000){std::ofstream out(directory+L"\\owner-lab-peer-status.tsv");out<<"mode\tprotocol_only_no_steam\nconnected\t"<<loop.connected<<"\nloaded\t"<<loaded<<"\nowner_packets\t"<<owners<<"\nelapsed_ms\t"<<now-start<<"\nerror\t"<<loop.error<<"\n";last_report=now;}
  Sleep(2);
 }
 return 0;
}
