-- Read-only schema of the mission-role boundary. Never calls the inventoried functions.
return function(output,id,context)
 local resolver=assert(loadfile(assert(os.getenv('AC8_LOCAL_SCRIPTS'))..'/guest_slot_resolver.lua'))()
 local r=context or resolver.resolve();local f=assert(io.open(output..'/guest-role-schema-'..id..'.tsv','w'))
 local function row(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v):gsub('[\t\r\n]',' ')end;f:write(table.concat(t,'\t'),'\n')end
 local function valid(o)return o and o:IsValid()end
 local seen={}
 local function schema(c)
  for depth=1,16 do
   if not valid(c)then return end;local name=c:GetFullName()
   if seen[name]or name:find('/Script/Engine.',1,true)or name:find('/Script/CoreUObject.',1,true)then return end;seen[name]=true
   row('class',name,string.format('0x%x',c:GetAddress()))
   local count=0;c:ForEachProperty(function(p)
    count=count+1;assert(count<=1024,'Property budget')
    row('property',name,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal(),string.format('0x%x',p:GetAddress()))
   end)
   count=0;c:ForEachFunction(function(fn)
    count=count+1;assert(count<=1024,'Function budget')
    local n=fn:GetFName():ToString();row('function',name,n,string.format('0x%x',fn:GetAddress()))
    fn:ForEachProperty(function(p)row('argument',name,n,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal(),string.format('0x%x',p:GetAddress()))end)
   end)
   c=c:GetSuperStruct()
  end
 end
 local ok,err=pcall(function()
  for _,o in ipairs({r.unit,r.target,r.component,r.host_player,r.controller})do
   assert(valid(o),'Stale inspection context')
   row('object',o:GetFullName(),string.format('0x%x',o:GetAddress()));schema(o:GetClass())
  end
  local related={r.host_player.LiveHUDCache,r.target.LiveHUDCache}
  if not context then related[#related+1]=r.target.WingmanSystemComponent end
  for _,o in ipairs(related)do
   if valid(o)then row('object',o:GetFullName(),string.format('0x%x',o:GetAddress()));schema(o:GetClass())end
  end
  local hud=r.host_player.LiveHUDCache
  if valid(hud)and valid(hud.TargetContainerManager)then local o=hud.TargetContainerManager;row('object',o:GetFullName(),string.format('0x%x',o:GetAddress()));schema(o:GetClass())end
  for _,o in ipairs(FindAllOf('LiveWingmanManager')or{})do if valid(o)then row('object',o:GetFullName(),string.format('0x%x',o:GetAddress()));schema(o:GetClass())end end
  for _,n in ipairs({'LiveGameMode','LiveGameState','LiveGameInstance','LiveAIWingmanSystemComponent','LiveBlueprintLibrary',
   'LiveUnitLifeManager','LiveUnitLifeActor','LiveWingmanManager','LiveSetGameObjectDisplayName','LiveSetActiveGameObjectExecution',
   'LiveWingmanJoinOrLeaveExecution','LiveTakeDamageUnitHealth','LiveUnitDamageTrigger','LiveDestroyUnitExecution','LiveSpawnWingmanExecution',
   'LiveAIGameObject','LiveIGCAIGameObject','LiveWingmanHUDLocatorForceDisplay','LiveWingmanHUDContainerForceDisplay',
   'LiveHasHealthInterface','LiveManipulableObjects','LiveManipulableObjectsWrapper','LiveWorldDataInterface','LiveWorldData',
   'LiveUnitLife','LiveUnitLifeItem','LiveUnitLifeList','LiveUnitLifeManager','LiveSetHealth','LiveSetMaxHealthExecution',
   'LiveSetMinHealthExecution','LiveUnitHealthDisplaySwitch','LiveSetActiveGameObjectExecution','LiveWingmanJoinOrLeaveExecution'})do
   local c=StaticFindObject('/Script/Live.'..n);if valid(c)then schema(c)else row('missing_class',n)end
  end
  for _,o in ipairs(context and(context.extra or{})or{})do if valid(o)then row('object',o:GetFullName(),string.format('0x%x',o:GetAddress()));schema(o:GetClass())end end
  if not context then resolver.verify(r)end
 end)
 row('summary',ok,err or'');f:close();assert(ok,err)
end
