#pragma once
#include <cstdint>
#include <vector>
namespace ac8story {
// Match the stock Unit-name OR group-name selector. UnitList membership is
// independently required: a matching FName alone is not an event assignment.
inline bool selected(uintptr_t unit,const std::vector<uintptr_t>& units,uint64_t key,
 const std::vector<uint64_t>& groups,uint64_t wanted_key,uint64_t wanted_group){
 bool present=false;for(auto p:units)present|=p==unit;
 if(!present)return false;
 if(key==wanted_key)return true;
 for(auto group:groups)if(group==wanted_group)return true;
 return false;
}
}
