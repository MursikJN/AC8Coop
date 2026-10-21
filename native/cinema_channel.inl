// Worker only. This channel never invokes engine code or evaluates text.
namespace coop28 {
static uint64_t sent_at=0,written_sequence=0;
static ac8cinema::Descriptor pinned;
static void reset(){cinema_pending={};cinema_rx=cinema_tx=sent_at=written_sequence=0;pinned={};}
static bool number(const std::string&s,uint64_t&v){v=0;if(s.empty()||s.size()>20)return false;for(char c:s){if(c<'0'||c>'9'||v>(UINT64_MAX-unsigned(c-'0'))/10)return false;v=v*10+unsigned(c-'0');}return true;}
static void files(ac8session::State&s,const wchar_t*folder,uint64_t token,uint64_t now){
 if(s.stage!=ac8session::Stage::intro_loading&&s.stage!=ac8session::Stage::cutscene)return;
 const auto base=std::wstring(folder);
 if(role==Role::guest){
  const auto&d=cinema_pending;if(!d.sequence||d.sequence==written_sequence||d.epoch!=s.epoch||d.revision!=s.revision||d.scene!=s.scene)return;
  const auto temp=base+L"\\cinema-client.tmp",target=base+L"\\cinema-client.tsv";
  FILE*f=_wfsopen(temp.c_str(),L"wb",_SH_DENYWR);if(!f)return;
  fprintf(f,"config_token\t%llu\nepoch\t%u\nrevision\t%u\nscene\t%u\nkind\t%u\nduration_ms\t%u\nasset\t%s\nviewer\t%s\noptions\t%s\n",static_cast<unsigned long long>(token),d.epoch,d.revision,d.scene,d.kind,d.duration_ms,d.asset.c_str(),d.viewer.c_str(),d.options.c_str());fclose(f);
  if(MoveFileExW(temp.c_str(),target.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))written_sequence=d.sequence;return;
 }
 if(now-sent_at<250)return;
 FILE*f=_wfsopen((base+L"\\cinema-host.tsv").c_str(),L"rb",_SH_DENYNO);if(!f)return;
 char bytes[2049]{};const auto n=fread(bytes,1,sizeof(bytes),f);fclose(f);if(!n||n>2048)return;
 const std::string text(bytes,n);if(text.find('\0')!=std::string::npos)return;
 const char*keys[]={"config_token","epoch","revision","scene","kind","duration_ms","asset","viewer","options"};std::string values[9];size_t pos=0;
 for(size_t i=0;i<9;++i){auto end=text.find('\n',pos);if(end==std::string::npos)return;auto line=text.substr(pos,end-pos);pos=end+1;auto tab=line.find('\t');if(tab==std::string::npos||line.substr(0,tab)!=keys[i])return;values[i]=line.substr(tab+1);}
 if(pos!=text.size())return;uint64_t nums[6]{};for(size_t i=0;i<6;++i)if(!number(values[i],nums[i]))return;
 if(nums[0]!=token||nums[1]!=s.epoch||nums[2]!=s.revision||nums[3]!=s.scene||nums[4]>2||nums[5]>3600000||cinema_tx==UINT64_MAX)return;
 ac8cinema::Descriptor d;d.sender=local_id;d.session=session.nonce;d.echo=session.remote;d.sequence=cinema_tx+1;d.epoch=s.epoch;d.revision=s.revision;d.scene=s.scene;d.kind=uint32_t(nums[4]);d.duration_ms=uint32_t(nums[5]);d.asset=values[6];d.viewer=values[7];d.options=values[8];
 if(!ac8cinema::valid(d))return;
 // A descriptor cannot change beneath a peer's prepared acknowledgement.
 if(pinned.scene==d.scene&&pinned.revision==d.revision&&(pinned.asset!=d.asset||pinned.kind!=d.kind||pinned.viewer!=d.viewer||pinned.options!=d.options||pinned.duration_ms!=d.duration_ms)){connection_ended("cinema_descriptor_changed");return;}
 const auto data=ac8cinema::encode(d);
 if(api.send(api.sockets,connection,data.data(),uint32(data.size()),k_nSteamNetworkingSend_ReliableNoNagle,nullptr)==k_EResultOK){cinema_tx=d.sequence;pinned=d;sent_at=now;}
}
}
