#pragma once
#include <string>
namespace ac8menu {
struct Settings {std::string role,peer;};
inline bool parse(const std::string& text,Settings& out){
 if(text.empty()||text.size()>256)return false;
 Settings result;bool format=false,mission=false,plane=false;size_t begin=0;unsigned count=0;
 while(begin<text.size()){
  const auto end=text.find('\n',begin);auto line=text.substr(begin,end==std::string::npos?std::string::npos:end-begin);
  if(!line.empty()&&line.back()=='\r')line.pop_back();begin=end==std::string::npos?text.size():end+1;
  if(line.empty())return false;const auto tab=line.find('\t');if(tab==std::string::npos||line.find('\t',tab+1)!=std::string::npos)return false;
  const auto key=line.substr(0,tab),value=line.substr(tab+1);++count;
  if(key=="format"){if(format||value!="ac8-coop-menu-v1")return false;format=true;}
  else if(key=="role"){if(!result.role.empty()||(value!="host"&&value!="guest"))return false;result.role=value;}
  else if(key=="peer"){if(!result.peer.empty()||value.size()!=17||value.find_first_not_of("0123456789")!=std::string::npos||value[0]=='0')return false;result.peer=value;}
  else if(key=="mission"){if(mission||value!="7")return false;mission=true;}
  else if(key=="plane"){if(plane||value!="23")return false;plane=true;}
  else return false;
 }
 if(count!=5||!format||!mission||!plane||result.role.empty()||result.peer.empty())return false;
 out=result;return true;
}
}
