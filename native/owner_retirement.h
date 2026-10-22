#pragma once
#include "plane_flight_core.h"
namespace ac8owner {
// A cold rollback may never allocate Parts/Network. Missing children are not
// pending allocations; an unknown allocation result still blocks completion.
inline bool retirement_complete(const plane_flight::Ledger&l,bool children_retired,bool camera_retired){
 return l.attempted&&l.plane_retired&&(!l.raw_network||l.network_retired)&&
  (!l.raw_parts||l.parts_retired)&&!l.unknown_spawn&&!l.unknown_network&&!l.unknown_parts&&
  children_retired&&camera_retired;
}
}
