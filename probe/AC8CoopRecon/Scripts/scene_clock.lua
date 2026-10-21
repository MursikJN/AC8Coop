-- Wall time from the engine, including while the world is paused. os.clock()
-- is process CPU time and must never be used for network freshness leases.
local M={}
function M.milliseconds(context,gameplay)
 assert(context and context:IsValid(),'Clock world unavailable')
 gameplay=gameplay or StaticFindObject('/Script/Engine.Default__GameplayStatics')
 assert(gameplay and gameplay:IsValid(),'Clock engine library unavailable')
 local seconds=gameplay:GetRealTimeSeconds(context)
 assert(type(seconds)=='number'and seconds==seconds and seconds>=0 and seconds<1e9,'Invalid engine wall clock')
 return seconds*1000
end
return M
