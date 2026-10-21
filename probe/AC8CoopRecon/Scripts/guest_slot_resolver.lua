-- r14 read-only resolver. Never caches a mission actor across resolve() calls.
-- No possession, spawn, AI mutations, or raw-memory properties.
local M={}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
local function in_world(o,w)return valid(o)and same(o:GetWorld(),w)end
local function text(v)return type(v)=='string'and v or v:ToString()end
function M.resolve(api)
 api=api or{find=FindAllOf,static=StaticFindObject}
 local controllers={}
 for _,pc in ipairs(api.find('LivePlayerController')or{})do
  if valid(pc)and valid(pc.Pawn)and pc.Pawn:IsA('/Script/Live.LivePlayerPlane')and not pc.Pawn.bIsIGCActor then
   local w=pc:GetWorld()
   if valid(w)and w:GetFullName():find('Mission007',1,true)and in_world(pc.Pawn,w)then controllers[#controllers+1]=pc end
  end
 end
 assert(#controllers==1,'Need one current host player controller')
 local pc=controllers[1];local world=pc:GetWorld();local player=pc.Pawn
 local wings,by_role={},{}
 for _,p in ipairs(api.find('LiveAIWingmanPlane')or{})do
  if in_world(p,world)and p.bIsActivated and not p.bIsIGCActor and not p.bIsAnimationPlane then
   local role=text(p.ObjNameID):match('^ContainerAllyCallsign_Name_(Joker[234])$')
   if role then assert(not by_role[role],'Duplicate mission wingman role');by_role[role]=p;wings[#wings+1]=p end
  end
 end
 assert(#wings==3 and by_role.Joker2 and by_role.Joker3 and by_role.Joker4,'Wait for three current mission wingmen')
 local target=by_role.Joker2
 assert(not same(target,player),'Guest slot aliases host pawn')
 assert(target:GetClass():GetFullName()=='BlueprintGeneratedClass /Game/Blueprints/Vehicle/AI/Wingman/BP_WOP1023_f14d.BP_WOP1023_f14d_C','Baxter must use the F-14D wingman model')
 assert(text(target.CallsignId)=='ContainerAllyCallsign_Name_Professor','Baxter callsign does not match the mission role')
 local component=target.AIStateComponent
 assert(valid(component)and same(component.Owner,target)and same(component,target.AIWingmanStateComponent),'Fresh AI component ownership mismatch')
 local unit,matches=nil,0
 local arrays={'RootAIGameObjects','ChildAIGameObjects','GroupLeadPlanes','AliveChildAIGameObjects'}
 for _,candidate in ipairs(api.find('LiveWingmanUnit')or{})do
  if in_world(candidate,world)then
   local hits=0
   for _,key in ipairs(arrays)do
    local a=candidate[key];local n=a:GetArrayNum();assert(n<=16,'Wingman array budget')
    for i=1,n do if same(a[i]:Get(),target)then hits=hits+1 end end
   end
   if hits>0 then
    assert(hits==4,'Baxter role arrays are incomplete or contain duplicate entries')
    for _,key in ipairs(arrays)do assert(candidate[key]:GetArrayNum()==1,'Baxter unit is not a singleton')end
    unit=candidate;matches=matches+1
   end
  end
 end
 assert(matches==1 and valid(unit),'Need one verified Baxter mission unit')
 local player_class_path='/Game/Blueprints/Vehicle/Player/Plane/PP0023_f14d/BP_PlayerPlane_PP0023_f14d.BP_PlayerPlane_PP0023_f14d_C'
 local player_class=api.static(player_class_path)
 -- Absence is evidence for the asset-loading step, not permission to use the AI flight engine.
 return {world=world,controller=pc,host_player=player,target=target,component=component,unit=unit,
  role='Joker2',slot=1,aircraft=23,other_wingmen={by_role.Joker3,by_role.Joker4},
  player_class_path=player_class_path,player_class_loaded=valid(player_class),player_class=player_class,
  target_name=target:GetFullName(),unit_name=unit:GetFullName()}
end
function M.verify(previous,api)
 local current=M.resolve(api)
 assert(same(previous.world,current.world)and same(previous.controller,current.controller)and same(previous.host_player,current.host_player),'Host mission identity changed')
 assert(previous.target_name==current.target_name and previous.unit_name==current.unit_name and same(previous.target,current.target)and same(previous.unit,current.unit)and same(previous.component,current.component),'Wingman identity changed; resolve the new mission graph')
 return current
end
return M
