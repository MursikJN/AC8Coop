-- Automatic counterpart of the previously observed r19 handoff. Only the
-- authenticated host invokes it, after the mission has spawned all four roles.
local M={}
local function valid(o)return o and o:IsValid()end
local function address(o)assert(valid(o));return string.format('0x%x',o:GetAddress())end
function M.new(c,output,source,log)
 local resolver=assert(loadfile(source..'/guest_slot_resolver.lua'))()
 local assets=assert(loadfile(source..'/guest_player_asset.lua'))()
 local pause=assert(loadfile(source..'/mission_sync_pause.lua'))().new(output,source)
 local dll=source..'/../../../ac8_guest_player_init_r19.dll'
 local calls={};for _,name in ipairs({'flight_preflight','flight_run','flight_cleanup','guest_model_trial','guest_role_trial','guest_role_detach_trial','guest_role_retire','guest_role_poll','guest_role_visual_prepare','guest_role_visual_finish'})do calls[name]=assert(package.loadlib(dll,'luaopen_ac8_'..name))end
 local s={phase='waiting_mission_roles',ready=false}
 local function write(name,body)local f=assert(io.open(output..'/'..name,'wb'));f:write(body);f:close()end
 local function status()
  local f=assert(io.open(output..'/plane-flight-status.tsv','rb'));local text=f:read(8193);f:close();assert(#text<=8192)
  local r={};for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)')do r[k]=v end;return r
 end
 local function detail(expected)local r=status();assert(r.native_detail==expected,'Подготовка Бакстера: '..tostring(r.native_detail));return r end
 local function offset(o,key)
  local cl=o:GetClass();for _=1,20 do if not valid(cl)then break end;local found
   cl:ForEachProperty(function(p)if p:GetFName():ToString()==key then assert(p:GetClass():GetFName():ToString()=='ObjectProperty');found=p:GetOffset_Internal();return true end end)
   if found then return found end;cl=cl:GetSuperStruct()
  end;error('Missing property '..key)
 end
 local function begin()
  assert(c.role=='host'and c.view().connected and c.snapshot.phase=='6','Нет активного вылета хоста.')
  pause.command('acquire');s.held=true;s.phase='preparing_player';s.stamp='coop27_'..c.token..'_'..c.snapshot.generation
  write('guest-role-peer.txt',assert(c.snapshot.peer))
  assets.with_class(resolver,function(r,cdo)
   s.graph=r
   write('guest-player-target.tsv','format\tac8-guest-f14-class-v1\ncreated_unix\t'..os.time()..'\nclass\t'..address(r.player_class)..'\ncdo\t'..address(cdo)..'\nplane_type\t23010\n')
   local p,rot=r.target:K2_GetActorLocation(),r.target:K2_GetActorRotation()
   local rows={'format\tac8-plane-flight-v1','stamp\t'..s.stamp,'created_unix\t'..os.time()}
   for _,e in ipairs({{'world',r.world},{'controller',r.controller},{'pawn',r.host_player},{'plane_class',r.host_player:GetClass()}})do rows[#rows+1]=e[1]..'\t'..address(e[2])end
   rows[#rows+1]='pc_pawn_offset\t'..offset(r.controller,'Pawn');rows[#rows+1]='plane_controller_offset\t'..offset(r.host_player,'Controller')
   for _,e in ipairs({{'location_x',p.X},{'location_y',p.Y},{'location_z',p.Z},{'rotation_pitch',rot.Pitch or rot.pitch},{'rotation_yaw',rot.Yaw},{'rotation_roll',rot.Roll}})do assert(type(e[2])=='number');rows[#rows+1]=e[1]..'\t'..string.format('%.17g',e[2])end
   write('plane-flight-request.tsv',table.concat(rows,'\n')..'\n')
   calls.flight_preflight();assert(status().status=='ready','Player preflight refused')
   calls.flight_run();local prepared=status();assert(prepared.status=='prepared'and prepared.finished_ready=='1','Player initialization refused')
   for _,o in ipairs(FindAllOf('BP_PlayerPlane_PP0023_f14d_C')or{})do if valid(o)and address(o)==prepared.owned then assert(not s.player);s.player=o end end
   assert(valid(s.player)and not s.player.bIsActivated,'Own F-14D missing');s.player:SetActorHiddenInGame(true);s.player:SetActorEnableCollision(false)
   assert(loadfile(source..'/guest_role_adapter.lua'))().prepare(output,resolver,r,s.player)
   calls.guest_model_trial();detail('independent_model_and_role_preparation_verified_no_commit')
   calls.guest_role_trial();detail('unit_health_location_name_forwarded_and_restored')
   local managers=FindAllOf('LiveWingmanManager')or{};assert(#managers==1 and valid(managers[1]));s.manager=managers[1]
   write('guest-role-manager.txt',address(s.manager));calls.guest_role_detach_trial();detail('npc_detachment_and_unit_forwarding_restored')
   resolver.verify(r);write('role-retire-armed.txt',s.stamp);calls.guest_role_retire();assert(status().status=='replacement_pending','NPC retirement refused')
   s.committed=true;s.phase='retiring_npc';s.retire_at=c.now;s.poll_at=0;log('coop_role_retiring',s.stamp)
  end)
 end
 function s.update()
  if s.error or s.ready then return end
  local ok,err=xpcall(function()
   if not s.committed then
    local available,r=pcall(resolver.resolve);if not available then return end
    local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics');if gameplay:IsGamePaused(r.world)then return end
    begin()
   elseif c.now-s.poll_at>=250 then
    s.poll_at=c.now
    assert(c.now-s.retire_at<10000,'NPC retirement timeout')
    if not s.collected and c.now-s.retire_at>=500 then StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):CollectGarbage();s.collected=true end
    calls.guest_role_poll();local r=status();if r.native_detail=='npc_retirement_pending'then return end
    detail('npc_retired_unit_preserved_player_reserved');calls.guest_role_visual_prepare();detail('replacement_visibility_prepared_stock_activation_pending')
    s.player:SetActorHiddenInGame(false);s.player:SetActorEnableCollision(false);s.player:SetActive(true,false,false)
    calls.guest_role_visual_finish();detail('four_plane_role_replacement_visual_ready_input_unbound')
    s.player:SetActorEnableCollision(false)
    s.runtime=assert(loadfile(source..'/guest_role_runtime.lua'))().start(output,source);_G.AC8GuestRoleRuntime=s.runtime
    assert(s.runtime.active,'Story role adapter refused');s.ready=true;s.phase='ready';pause.command('release');s.held=false;log('coop_role_ready',s.stamp)
   end
  end,debug.traceback)
  if not ok then
   s.error=tostring(err);s.phase='error';log('coop_role_error',s.error)
   if not s.committed then calls.flight_cleanup()end
   -- Keep the owned pause on a failed handoff. Never revive a retired NPC.
  end
 end
 return s
end
return M
