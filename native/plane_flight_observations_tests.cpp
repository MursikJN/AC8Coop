// Include the real serializer so the two parser fixtures exercise actual output.
// No game pointer or native game function is used by this executable.
#include "plane_flight_probe.cpp"
#include <limits>
struct ObservationMock {
 std::array<unsigned char,0x400> memory{};bool scene_type=true,stable=true,readable=true;unsigned transform_reads=0;
 ObservationMock(){uintptr_t owner=0x10000;std::memcpy(memory.data()+0x90,&owner,8);double xyz[3]={100,200,300};std::memcpy(memory.data()+0x220,xyz,24);}
 bool identify(uintptr_t p,observation::Identity& out){if(p!=0x20000)return false;out={};out.pointer=p;out.index=1;out.serial=2;out.klass=0x30000;out.vtable=0x40000;return true;}
 bool unchanged(const observation::Identity&){return stable;}
 bool scene(uintptr_t){return scene_type;}
 bool read(uintptr_t p,void* out,size_t size){if(p==0x20200)++transform_reads;if(!readable||p<0x20000||p>0x20400||size>0x20400-p)return false;std::memcpy(out,memory.data()+p-0x20000,size);return true;}
};
void observation_check(bool ok,const char* label){if(!ok){std::printf("FAIL %s\n",label);std::exit(1);}}
observation::Actor synthetic_actor(uintptr_t p,const observation::Vec& xyz){
 observation::Actor a;a.identity_valid=true;a.identity.pointer=p;a.identity.index=1;a.identity.serial=2;a.flags_valid=true;
 a.root_pointer=p+0x1000;a.root.identity.pointer=a.root_pointer;a.root.identity.index=3;a.root.identity.serial=4;
 a.root.identity_valid=true;a.root.scene_verified=true;a.root.owner_matches=true;a.root.owner=p;
 a.root.transform_valid=true;a.root.raw_transform_valid=true;a.root.flags_valid=true;a.root.world=xyz;
 std::memcpy(a.root.raw_transform.data()+0x20,xyz.data(),24);return a;
}
int wmain(int argc,wchar_t** argv){
 unsigned tests=0;
 {observation::Schedule s;unsigned count=0;for(uint64_t t=0;t<20000;t+=10)if(s.pose(t,t==0)!=observation::Stage::none)++count;
  if(s.cleanup()!=observation::Stage::none)++count;observation_check(count==5&&s.cleanup()==observation::Stage::none&&s.pose(20000,false)==observation::Stage::none,"five bounded samples; none after cleanup");++tests;}
 {observation::Schedule s;observation_check(s.cleanup()==observation::Stage::before_destroy&&s.pose(0,true)==observation::Stage::none,"early cleanup prevents later sampling");++tests;}
 {unsigned failures=0,continued=0;observation::best_effort([]()->bool{throw 1;},failures);++continued;observation::best_effort([](){return false;},failures);++continued;observation_check(failures==2&&continued==2,"failed telemetry never suppresses following cleanup work");++tests;}
 {ObservationMock r;observation::Scene s;observation_check(observation::capture_scene(r,0x20000,0x10000,s)&&s.world[0]==100&&s.world[2]==300&&s.raw_transform_valid,"confirmed scene position window");++tests;}
 {ObservationMock r;r.scene_type=false;observation::Scene s;observation_check(!observation::capture_scene(r,0x20000,0x10000,s)&&r.transform_reads==0&&!s.transform_valid,"no scene layout read without class gate");++tests;}
 {ObservationMock r;observation::Scene s;observation_check(!observation::capture_scene(r,0x20000,0x99999,s)&&r.transform_reads==0&&!s.owner_matches,"foreign owner rejects scene data");++tests;}
 {ObservationMock r;r.stable=false;observation::Scene s;observation_check(!observation::capture_scene(r,0x20000,0x10000,s)&&!s.identity_valid&&!s.transform_valid&&!s.scene_verified,"changed identity invalidates captured fields");++tests;}
 {ObservationMock r;double nan=std::numeric_limits<double>::quiet_NaN();std::memcpy(r.memory.data()+0x220,&nan,8);observation::Scene s;
  observation_check(!observation::capture_scene(r,0x20000,0x10000,s)&&s.raw_transform_valid&&!s.transform_valid,"nonfinite position retains raw bytes but not decoded validity");++tests;}
 {auto a=synthetic_actor(0x10000,{0,0,0}),b=synthetic_actor(0x10000,{3,4,0}),source=synthetic_actor(0x30000,{0,0,0});auto m=observation::metrics(a,b,source,{3,4,0},true);
  observation_check(m.actual_step.valid&&m.actual_step.distance==5&&m.request_error.distance==0&&m.source_delta.distance==5,"actual step target error and source distance");++tests;}
 {auto a=synthetic_actor(0x10000,{0,0,0}),b=a;b.root.identity.serial++;auto m=observation::metrics(a,b,a,{0,0,0},true);observation_check(!m.actual_step.valid,"root replacement is not reported as movement");++tests;}
 {observation::Actor a;auto m=observation::metrics(a,a,a,{0,0,0},true);observation_check(!m.actual_step.valid&&!m.request_error.valid&&!m.source_delta.valid,"invalid observations produce invalid metrics");++tests;}
 {ObservationJson j;observation::Actor a;observation_actor(j,a);observation_check(j.text.find("\"hidden_bit80\":null")!=std::string::npos&&j.text.find("\"active3f4\":null")!=std::string::npos,"missing flags do not claim visible or active state");++tests;}
 {ObservationJson j;j.vec({std::numeric_limits<double>::infinity(),0,0},true);observation_check(j.text=="null","serializer never emits infinity or NaN");++tests;}
 observation_check(argc==2,"fixture directory required");directory=argv[1];
 const auto path=directory+L"\\plane-flight-observations-r4.jsonl";HANDLE f=CreateFileW(path.c_str(),GENERIC_WRITE,FILE_SHARE_READ,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);observation_check(f!=INVALID_HANDLE_VALUE,"open fixture file");CloseHandle(f);
 ObservationFrame frame;frame.source_before=synthetic_actor(0x10000,{0,0,0});frame.source_after=frame.source_before;
 frame.owned_before=synthetic_actor(0x30000,{0,0,0});frame.owned_after=synthetic_actor(0x30000,{30000,10000,2000});frame.requested={30000,10000,2000};frame.requested_valid=true;
 observation_check(emit_observation_frame(observation::Stage::seed,0,frame,true,true),"write actual valid JSONL schema");++tests;
 frame={};observation_check(!emit_observation_frame(observation::Stage::before_destroy,15000,frame,false,false),"invalid sample recorded but reported unavailable");++tests;
 std::printf("%u observation tests passed; two synthetic actual-serializer fixtures written; no native execution\n",tests);return 0;
}
