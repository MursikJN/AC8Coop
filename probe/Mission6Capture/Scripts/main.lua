-- Dedicated offline observer. No r31 adapters, menu automation, native calls or gameplay hooks.
if os.getenv('AC8_MISSION6_CAPTURE')~='25201480' then return end
local output=assert(os.getenv('AC8_MISSION6_OUTPUT'))
local source=assert(os.getenv('AC8_MISSION6_SCRIPTS'))
local C=assert(loadfile(source..'/capture.lua'))()
local automation
if os.getenv('AC8_CAPTURE_AUTOMATION')=='1'then automation=assert(loadfile(source..'/automation.lua'))().new(output)end
local serial,busy,stopped,last,last_full=0,false,false,'',0
-- Event graph and indexed tables first; one category discovery or one root per tick.
local queries={'LiveEventSubsystem','LiveEventContainer','LiveIndexSavedDataTable',
 'LiveCampaignMissionConfig','LiveEventPackage','LiveEventData','LiveAIActionEventComponent',
 'LiveRandomEventSubsystem','LiveMissionRoomMemberManager','LiveAIWingmanPlane',
 'LiveAIWingmanUnit','LiveAircraftSelector','LiveHangarManager','GameModeBase','LiveGameState',
 'LiveCinematicsCinemaPlayer','LiveCinematicsPlayableStateManager','LiveCinematicsWorldSubsystem',
 'LiveStreamingLoader','LevelStreaming','DataTable'}
local query_index,names,name_index,cycle=1,{},1,0
local active=false
local baxter,orders
if os.getenv('AC8_BAXTER_STUDY')=='1'then
 local B=assert(loadfile(source..'/baxter.lua'))();queries=B.queries;baxter=B.new(C)
 orders=assert(loadfile(source..'/orders.lua'))().new({find=FindAllOf,register=RegisterCustomProperty,types=PropertyTypes,is_game_thread=IsInGameThread})
end
local function clean(v)return tostring(v):gsub('\\','\\\\'):gsub('\t','\\t'):gsub('\r','\\r'):gsub('\n','\\n')end
local function append(kind,detail)
 local f=assert(io.open(output..'/timeline.tsv','a'))
 f:write(os.date('!%Y-%m-%dT%H:%M:%SZ'),'\t',kind,'\t',clean(detail),'\n');f:close()
end
local function begin_cycle(reason)
 query_index,names,name_index=1,{},1;cycle=cycle+1;active=true
 append('cycle_start','cycle='..cycle..';reason='..reason)
end
local function step(reason)
 serial=serial+1
 local path=output..'/snapshot-'..string.format('%05d',serial)..'.tsv'
 local f=assert(io.open(path,'w'));f:write('kind\tpath\ttype_or_status\tvalue\tdetail\n')
 local function emit(...)
  local a={...};for i=1,5 do if a[i]==nil then a[i]=''end;a[i]=clean(a[i])end
  f:write(table.concat(a,'\t'),'\n')
 end
 local query=queries[query_index]
 local ok,err=pcall(function()
  emit('cycle',cycle,'category',query,reason)
  if name_index<=#names then
   local root=names[name_index];name_index=name_index+1
   C.capture({find=FindAllOf,clock=os.clock,emit=emit},reason,nil,{query=query,name=root})
  else
   if #names>0 then query_index=query_index+1;query=queries[query_index]end
   if not query then active=false;last_full=os.time();emit('summary',reason,'cycle_finished','','no_atomic_graph_claim');return end
   names={};name_index=1
   local discovered=C.discover(FindAllOf,query)
   for _,n in ipairs(discovered)do names[#names+1]=n;emit('discovered',query,'object_name',n)end
   emit('query',query,'instances',#names)
   emit('summary',reason,'discovery_finished','','strings_only;native_private_fields=not_captured')
   if #names==0 then query_index=query_index+1 end
   if query_index>#queries then active=false;last_full=os.time()end
  end
 end)
 if not ok then
  emit('fatal',query or'','slice_error',err,'')
  -- Do not repeatedly query a failing category; do not keep partial discovery state.
  names={};name_index=1;query_index=query_index+1
  if query_index>#queries then active=false;last_full=os.time()end
 end
 f:close();append('snapshot',path)
end
local function schedule(reason)
 if busy or stopped then return end;busy=true
 local ok,err=pcall(ExecuteInGameThread,function()
  local ran,problem=pcall(function()
   assert(IsInGameThread(),'wrong_thread')
   for _,w in pairs(FindAllOf('World')or{})do
    if w:IsValid()then
     local driver=w.NetDriver
     if driver and driver:IsValid()then stopped=true;error('network_driver_present_capture_stopped')end
    end
   end
   local context=C.context(FindAllOf)
   if orders then
    local f=assert(io.open(output..'/orders.tsv','a'))
    local ok,err=pcall(orders.sample,context,function(...)
     local a={...};for i=1,5 do if a[i]==nil then a[i]=''end;a[i]=clean(a[i])end
     f:write(os.date('!%Y-%m-%dT%H:%M:%SZ'),'\t',table.concat(a,'\t'),'\n')
    end)
    f:close();if not ok then error(err)end
   end
   if baxter then
    local watch=baxter.next_watch(FindAllOf,context)
    if watch then
     serial=serial+1
     local path=output..'/watch-'..string.format('%05d',serial)..'.tsv'
     local f=assert(io.open(path,'w'));f:write('kind\tpath\ttype_or_status\tvalue\tdetail\n')
     local ok,err=pcall(function()
      C.capture({find=FindAllOf,clock=os.clock,emit=function(...)
       local a={...};for i=1,5 do if a[i]==nil then a[i]=''end;a[i]=clean(a[i])end
       f:write(table.concat(a,'\t'),'\n')
      end},'baxter_watch',nil,watch)
     end)
     f:close();append('watch',path)
     if not ok then error(err)end
    end
   end
   if automation then automation.tick()end
   if context~=last then
    append('context_change',context);last=context;begin_cycle('context_changed')
   elseif not active and(reason~='poll'or os.time()-last_full>=30)then begin_cycle(reason)end
   if active then step(reason)end
  end)
  busy=false
  if not ran then stopped=true;append('stopped',problem)end
 end)
 if not ok then busy=false;stopped=true;append('schedule_error',err)end
end
RegisterKeyBind(Key.F8,function()schedule('manual_F8')end)
RegisterKeyBind(Key.F10,function()stopped=true;append('stopped','manual_F10')end)
append('observer_ready','partitioned-v2;F8 next slice/start cycle;F10 stop;no pause or menu actions')
LoopAsync(2000,function()if stopped then return true end;schedule('poll')end)
