assert(os.getenv('AC8_STEAM_LOBBY')=='25201480','Steam lobby profile required')
local source=assert(os.getenv('AC8_LOBBY_SCRIPTS'))
local output=assert(os.getenv('AC8_COOP_RECON_OUTPUT'))
local dll=assert(os.getenv('AC8_LOBBY_DLL'))
local native={}
local coop=os.getenv('AC8_STEAM_COOP')=='25201480'
local cinema_sync=os.getenv('AC8_CINEMA_SYNC')=='25201480'
local policy=os.getenv('AC8_SESSION_POLICY')=='25201480'
local launch_role=os.getenv('AC8_LOBBY_ROLE')
if policy then assert(os.getenv('AC8_SAVE_POLICY')==(launch_role=='host'and'host-persistent'or'guest-discarded'),'Изолированный профиль роли не подтверждён лаунчером.')end
for _,name in ipairs({'start','stop','tick'})do native[name]=assert(package.loadlib(dll,'luaopen_ac8_lobby24_'..name))end
if os.getenv('AC8_STEAM_INVITES')=='25201480'then
 native.invites_tick=assert(package.loadlib(dll,'luaopen_ac8_invites25_tick'))
 native.invites_open=assert(package.loadlib(dll,'luaopen_ac8_invites25_open'))
end
if coop then
 for _,name in ipairs({'start','tick','stop','loaded','capture_input'})do native['pilot_'..name]=assert(package.loadlib(dll,'luaopen_ac8_pilot_'..name))end
 native.capture_vote=assert(package.loadlib(dll,'luaopen_ac8_coop27_capture_vote'))
end
local function log(event,detail)
 local f=io.open(output..'/steam-menu.log','a');if f then f:write(os.date('%Y-%m-%d %H:%M:%S'),'\t',event,'\t',tostring(detail or''):gsub('[\r\n]',' '),'\n');f:close()end
end
local menu=assert(loadfile(source..'/coop_main_menu.lua'))()
local catalog=assert(loadfile(source..'/coop_menu_catalog.lua'))()
if coop then _G.AC8LocalMenuDll=source..'/../../../ac8_menu_route_r13.dll'end
local controller=assert(loadfile(source..'/steam_lobby_services.lua'))().new(output,native,nil,{mission_sync=coop,cinema_sync=cinema_sync,session_policy=policy,launch_role=launch_role})
local options={compact=true,source=source,catalog=catalog,is_host=os.getenv('AC8_LOBBY_ROLE')~='guest',
 view=controller.view,status=controller.status,create=controller.create,join=controller.join,leave=controller.leave,
 select=controller.select,ready=controller.ready,loadout=controller.loadout,open_hangar=coop and controller.open_hangar or nil,log=log,error=function(e)log('ui_error',e)end}
options.invite=native.invites_open and controller.invite or nil
options.fixed_role=policy and launch_role or nil
options.cancel=policy and controller.cancel or nil;options.restart=policy and controller.restart or nil
options.input_blocked=function()return controller.invite_status.overlay_active=='1'end
local ui;local shown_invite=0
local adapter,pilot,role,scene,client,room_token,last_scene= nil,nil,nil,nil,nil,nil,0
local function tick()
 local ok,err=pcall(function()
  if not ui then ui=menu.attach(options)end
  local visible=false;if ui then local valid,result=pcall(function()return ui.main:IsVisible()end);visible=valid and result==true end
  controller.set_menu_available(visible);controller.poll()
  if policy and visible and not controller.active and not controller.resume_checked and os.getenv('AC8_RESUME_HOST')then
   controller.resume_checked=true
   if launch_role=='host'then controller.create(6,1)else controller.join(os.getenv('AC8_RESUME_HOST'))end
   controller.join_notice=controller.join_notice+1
  end
  if coop and not controller.active and room_token and not role and(not pilot or not pilot.active)then
   if client then client.stop('left_room')end
   if controller.recovery_ui then controller.recovery_ui.stop();controller.recovery_ui=nil end
   controller.lifecycle=nil;controller.cinema=nil
   adapter,pilot,scene,client,room_token=nil,nil,nil,nil,nil
  end
  if coop and controller.active and controller.token~=room_token then
   assert(not room_token,'Для новой игровой сессии нужен новый процесс игры.')
   room_token=controller.token
   if policy then
    controller.lifecycle=assert(loadfile(source..'/session_lifecycle.lua'))().new(controller,output,source,log)
    controller.recovery_ui=assert(loadfile(source..'/session_recovery_ui.lua'))().new(controller,log)
   end
   if cinema_sync then controller.cinema=assert(loadfile(source..'/cinema_playback.lua'))().new(controller,output,source,log)end
   if controller.role=='host'then
    adapter=assert(loadfile(source..'/mission_sync_adapter.lua'))().new(controller,output,source,log)
    pilot=assert(loadfile(source..'/steam_coop_pilot.lua'))().new(controller,output,source,native,log)
    scene=assert(loadfile(source..'/scene_host.lua'))().new(output,source,controller,{find=FindAllOf,static=StaticFindObject,clock=function()return controller.now or 0 end})
   else
    local provider=assert(loadfile(source..'/steam_coop_client_world.lua'))().new(controller,output,source,log)
    client=assert(loadfile(source..'/steam_coop_client.lua'))().new(controller,output,source,native,log,provider)
   end
  end
  if coop and controller.active then
   local halted=policy and controller.lifecycle.update({adapter=adapter,pilot=pilot,role=role,client=client})
   if halted then
    -- No campaign routing, scene export or input is allowed after quiescence.
   elseif adapter then
    adapter.update()
    if controller.snapshot.phase=='6'and controller.view().connected and not adapter.error then
     role=role or assert(loadfile(source..'/steam_coop_role.lua'))().new(controller,output,source,log);role.update()
     if role.error then controller.error='Подготовка Бакстера: '..role.error end
     if role.ready and not pilot.active and not pilot.reason then pilot.try_start(role)end
    end
    if pilot then pilot.update(role)end
    if scene and(controller.now or 0)-last_scene>=200 then last_scene=controller.now;scene.update()end
   elseif client then client.update()end
   if controller.recovery_ui then local ok,e=pcall(controller.recovery_ui.update);if not ok then log('recovery_ui_error',e)end end
  end
  if ui and not ui.refresh()then ui=menu.attach(options)end
  if ui and visible and controller.join_notice>shown_invite then ui.ui_error=nil;ui.show();shown_invite=controller.join_notice;log('invite_room_opened')end
 end)
 if not ok then log('tick_error',err);if policy then controller.fault(tostring(err))end end
 ExecuteInGameThreadWithDelay(coop and 16 or 100,tick)
end
log(policy and'r29_loaded'or cinema_sync and'r28_loaded'or coop and'r27_loaded'or native.invites_tick and'r25_loaded'or'r24_loaded',coop and'Steam room, mission barriers and session-bound pilot; isolated guest world required'or'Steam lobby only; transport starts on Create/Join/accepted invite')
ExecuteInGameThreadWithDelay(1000,tick)
