-- Role preparation for the separately owned stock player plane.
-- No writes to the NPC, its Unit, AI containers, controller, camera or HUD.
local M={}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
function M.prepare(output,resolver,previous,player,api)
 api=api or{find=FindAllOf}
 local r=resolver.verify(previous,api.find and api.static and api or nil)
 assert(valid(player)and same(player:GetWorld(),r.world)and not same(player,r.host_player),'Foreign player plane')
 assert(player:GetClass():GetFullName()=='BlueprintGeneratedClass '..r.player_class_path,'Wrong player class')
 assert(player.PlaneTypeID==23010 and player.bHidden and not player.bIsActivated and not player:GetActorEnableCollision(),'Player preparation barrier missing')
 assert(not valid(player.Controller),'Guest must not take the host controller')
 local players=0
 for _,o in ipairs(api.find('LivePlayerPlane')or{})do
  if valid(o)and same(o:GetWorld(),r.world)and o.bIsActivated and not o.bIsIGCActor then assert(same(o,r.host_player),'Unexpected active player plane');players=players+1 end
 end
 assert(players==1,'Need one active host player plane before replacement')
 local property;local c=player:GetClass()
 for depth=1,16 do
  if not valid(c)then break end
  c:ForEachProperty(function(p)
   if p:GetFName():ToString()=='bHidden'then
    assert(p:GetClass():GetFName():ToString()=='BoolProperty'and p:GetOffset_Internal()==0x58,'Unexpected hidden property');property=p;return true
   end
  end)
  if property then break end;c=c:GetSuperStruct()
 end
 assert(property,'Reflected actor hidden flag missing')
 local f=assert(io.open(output..'/guest-role-request.tsv','w'))
 f:write('format\tac8-baxter-role-v1\ncreated_unix\t',os.time(),'\n')
 for _,entry in ipairs({{'npc',r.target},{'unit',r.unit},{'component',r.component},{'other0',r.other_wingmen[1]},{'other1',r.other_wingmen[2]},{'hidden_property',property}})do
  f:write(entry[1],'\t',string.format('0x%x',entry[2]:GetAddress()),'\n')
 end;f:close()
 return {role=r.role,slot=r.slot,aircraft=r.aircraft,player=player,unit=r.unit,npc=r.target,committed=false,input_allowed=false}
end
return M
