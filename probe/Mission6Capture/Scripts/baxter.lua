-- Read-only follow-up to observed Mission007 references. No UObject survives a tick.
local M={}
M.queries={'LiveSetIsInvincibleFromWingman','LiveInputWingmanStateStatement',
 'LiveWingmanJoinOrLeaveExecution','LiveWingmanOrderExecution','LiveEventContainer',
 'LiveWingmanManager','LiveAIWingmanStateComponent','LiveAIWingmanSystemComponent','BP_WingmanUnit_C',
 'LiveAIWingmanPlane','LiveAIChangePilotRankExecution',
 'LiveWingmanHUDContainerForceDisplay','LiveWingmanHUDLocatorForceDisplay',
 'LivePilotIDStatement','LiveAIEngagementOrder','LiveDestroyUnitExecution',
 'LiveUnitMoveActor','LiveUnitMoveExit','LiveCampaignMissionConfig'}
function M.new(C)
 local cursor=0
 return {next_watch=function(find,context)
  if not context:find('/Mission007/PL_Mission007',1,true)then cursor=0;return end
  local names=C.discover(find,'LiveAIWingmanStateComponent')
  local selected={}
  for _,n in ipairs(names)do
   if n:find('/Mission007/PL_Mission007',1,true)then selected[#selected+1]=n end
  end
  assert(#selected<=12,'wingman_watch_count_exceeded')
  if #selected==0 then cursor=0;return end
  cursor=cursor%#selected+1
  return {query='LiveAIWingmanStateComponent',name=selected[cursor]}
 end}
end
return M
