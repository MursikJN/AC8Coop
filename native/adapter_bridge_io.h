#pragma once
#include <cstdio>
#include <cstdlib>
#include <cerrno>
#include <map>
#include <string>
#include <share.h>
namespace ac8adapter {
inline bool stamp_valid(const std::string&s){return !s.empty()&&s.size()<=64&&s.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")==std::string::npos;}
// Read bounded text only; this helper never accesses a game object.
inline bool request(const std::wstring&path,std::map<std::string,std::string>&fields){
 FILE*f=_wfsopen(path.c_str(),L"rb",_SH_DENYNO);if(!f)return false;
 char bytes[1025]{};const auto n=fread(bytes,1,sizeof bytes,f);fclose(f);if(!n||n>1024)return false;
 const std::string text(bytes,n);size_t start=0;
 while(start<text.size()){
  auto end=text.find('\n',start);if(end==std::string::npos)return false;
  auto line=text.substr(start,end-start);start=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();
  auto tab=line.find('\t');if(tab==std::string::npos||!fields.emplace(line.substr(0,tab),line.substr(tab+1)).second)return false;
 }
 return true;
}
inline std::string echo(const std::wstring&path){
 std::map<std::string,std::string>fields;
 return request(path,fields)&&stamp_valid(fields["stamp"])?fields["stamp"]:std::string();
}
inline bool number(const std::string&s,unsigned long long&value){
 if(s.empty()||s.size()>20||s[0]=='-'||s[0]=='+')return false;
 char*end=nullptr;errno=0;value=strtoull(s.c_str(),&end,0);return !errno&&end==s.c_str()+s.size();
}
}
