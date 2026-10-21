-- r19 development lifecycle after the one-way native replacement. This is not
-- a guest connection or input grant. The public r13 launcher does not arm it.
local M={}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
local function receipt(output,name)
 local f=assert(io.open(output..'/'..name,'r'));local text=f:read('*a');f:close();local r={}
 for k,v in text:gmatch('([^\t\r\n]+)\t([^\r\n]*)')do assert(not r[k]);r[k]=v end;return r
end
function M.start(output,source)
 assert(os.getenv('AC8_LOCAL_ADAPTER_DEV')=='25201480','Development profile required')
 local role_dll=source..'/../../../ac8_guest_player_init_r19.dll'
 local story_dll=source..'/../../../ac8_guest_story_r19c.dll'
 local poll_role=assert(package.loadlib(role_dll,'luaopen_ac8_guest_role_poll'))
 local bind=assert(package.loadlib(story_dll,'luaopen_ac8_guest_story_bind'))
 local poll=assert(package.loadlib(story_dll,'luaopen_ac8_guest_story_poll'))
 local unbind=assert(package.loadlib(story_dll,'luaopen_ac8_guest_story_unbind'))
 local s={active=false,input_allowed=false,state='preparing',checks=0}
 local function save()
  local f=assert(io.open(output..'/guest-role-runtime-r19.tsv','w'))
  f:write('state\t',s.state,'\nactive\t',tostring(s.active),'\nchecks\t',s.checks,'\ninput_allowed\t0\nall_story_commands_bridged\t0\nspectator_camera_implemented\t0\ndeath_rule\tspectate_until_shared_restart\nreason\t',(s.reason or''):gsub('[\r\n\t]',' '),'\n');f:close()
 end
 function s.stop(reason)
  s.active=false;s.state='stopped';s.reason=reason
  if s.loop then CancelDelayedAction(s.loop);s.loop=nil end
  if s.marker then s.marker.stop(reason)end
  unbind();save()
 end
 local ok,err=xpcall(function()
  poll_role();local r=receipt(output,'guest-role-commit-r19.tsv')
  assert(r.npc_retired_verified=='1'and r.unit_preserved=='1'and r.player_visible_active=='1','Replacement not committed')
  for _,o in ipairs(FindAllOf('LivePlayerPlane')or{})do if valid(o)and string.format('0x%x',o:GetAddress())==r.player then s.player=o end end
  for _,o in ipairs(FindAllOf('LivePlayerController')or{})do if valid(o)and valid(o.Pawn)and o.Pawn.bIsActivated then assert(not s.pc);s.pc=o end end
  assert(valid(s.player)and valid(s.pc));s.host=s.pc.Pawn;s.world=s.player:GetWorld()
  assert(same(s.world,s.host:GetWorld())and not same(s.player,s.host))
  local f=assert(io.open(output..'/guest-story-request.tsv','w'))
  f:write('created_unix\t',os.time(),'\ncontroller\t',string.format('0x%x',s.pc:GetAddress()),'\nhost\t',string.format('0x%x',s.host:GetAddress()),'\n');f:close()
  bind();r=receipt(output,'guest-story-status-r19c.tsv');assert(r.bound=='1'and r.installed=='1',r.reason)
  if _G.AC8GuestRoleMarker then _G.AC8GuestRoleMarker.stop('attach_role_runtime')end
  s.marker=assert(loadfile(source..'/guest_role_marker.lua'))().new();_G.AC8GuestRoleMarker=s.marker
  s.marker.attach(s.player,s.pc)
  s.active=true;s.state='replacement_bound_guest_input_unavailable';save()
  s.loop=LoopInGameThreadAfterFrames(60,function()
   if not s.active then return end
   local checked,message=xpcall(function()
    assert(valid(s.player)and valid(s.world)and same(s.player:GetWorld(),s.world),'Replacement world ended')
    assert(same(s.pc.Pawn,s.host)and same(s.host.Controller,s.pc),'Host ownership changed')
    poll_role();local role=receipt(output,'guest-role-commit-r19.tsv')
    assert(role.npc_retired_verified=='1'and role.unit_preserved=='1','Native role expired')
    poll();local event=receipt(output,'guest-story-status-r19c.tsv');assert(event.reason=='unit_damage_binding_valid','Native event binding expired')
    s.checks=s.checks+1
    if s.player:GetHealth()<=0 then
     s.state='guest_dead_spectator_client_required';s.marker.stop('guest_dead')
    else assert(s.marker.active,'Nickname marker stopped: '..tostring(s.marker.reason))end
    save()
   end,debug.traceback)
   if not checked then s.stop(message)end
  end)
 end,debug.traceback)
 if not ok then s.stop(err);error(err)end
 return s
end
return M
