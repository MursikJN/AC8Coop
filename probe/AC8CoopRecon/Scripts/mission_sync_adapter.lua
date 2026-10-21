-- r26: checked stock route, explicit host loaded acknowledgements and real scene barriers.
local M={}
function M.new(controller,output,source,log,previous)
 local native=assert(loadfile(source..'/local_menu_native.lua'))().new(output)
 local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local guard=assert(loadfile(source..'/mission_sync_cinema_guard.lua'))().new(output,source)
 local pause=assert(loadfile(source..'/mission_sync_pause.lua'))().new(output,source)
 local ui_module=assert(loadfile(source..'/local_hangar_ui.lua'))()
 local status_ui=assert(loadfile(source..'/mission_sync_status_ui.lua'))().new(controller,log)
 local r=previous or{step=1,phase='idle',error=nil,scene_players={},sortie=false}
 local steps={{'main_campaign','LiveMenuMainTopWidget'},{'campaign_free_mission','LiveMenuCampaignTopWidget'},{'difficulty_pilot','LiveMenuCampaignFreeMissionDifficultyWidget'},{'mission6','LiveMenuCampaignFreeMissionWidget'},{'narrative','LiveMenuCampaignNarrativeSelectWidget'}}
 local function valid(o)return o and o:IsValid()end
 local function pc()return require('UEHelpers').GetPlayerController()end
 local function hold_world()
  local player=pc();assert(valid(player),'Нет контекста загрузки.')
  if not r.held_context then
   local state=pause.command('acquire');assert(state.held=='1','Нет владения паузой ожидания.');r.held_context=player
   r.hold_time=gameplay:GetTimeSeconds(player);log('world_held',player:GetWorld():GetFullName()..'/time='..r.hold_time)
  end
  -- The stock manager also freezes mission/UI timers that Unreal pause omits.
  -- Reassert our reason because loading scripts can replace the reason mask.
  local state=pause.command('acquire');assert(state.held=='1'and state.paused=='1','Штатная пауза не удержана.')
  assert(gameplay:IsGamePaused(player),'Мир не принял штатную паузу.')
  local elapsed=gameplay:GetTimeSeconds(player)-r.hold_time;assert(math.abs(elapsed)<0.001,'Мир продолжает идти во время ожидания.')
  if not r.hold_sample_at or controller.now-r.hold_sample_at>=1000 then
   r.hold_sample_at=controller.now
   local location=valid(player.Pawn)and player.Pawn:K2_GetActorLocation()or{X=0,Y=0,Z=0}
   local f=assert(io.open(output..'/world-hold-samples.tsv','a'))
   f:write(controller.now,'\t',controller.snapshot.phase,'\t',r.hold_time,'\t',gameplay:GetTimeSeconds(player),'\t',location.X,'\t',location.Y,'\t',location.Z,'\n');f:close()
  end
 end
 local function release_world()
  if r.held_context then
   assert(valid(r.held_context),'Контекст удерживаемого мира изменился.')
   -- Release only our reason; a stock cinematic/tutorial may retain its pause.
   local state=pause.command('release');assert(state.held=='0','Пауза ожидания не освобождена.')
   log('world_released','tick='..controller.now..'/held_time='..r.hold_time..'/remaining_flags='..state.flags)
  end
  r.held_context=nil;r.hold_time=nil;r.hold_sample_at=nil
 end
 local function strategy()
  local result
  for _,o in ipairs(FindAllOf('LiveSkipOperationPressHoldSkipStrategy')or{})do if valid(o)then
   local owner=o:GetOuter();if valid(owner)and owner:IsA('/Script/Live.LiveSkipOperationManager')and valid(owner.SkipOperationStrategy)and owner.SkipOperationStrategy:GetAddress()==o:GetAddress()then assert(not result,'Несколько обработчиков пропуска.');result=o end
  end end
  return result
 end
 local function protect_skip(v)
  local o=strategy();if not o then return nil end
  local key=o:GetFullName()
  if r.strategy_key~=key then
   local next_scene=not controller.cinema and r.strategy_key and v.phase==2 and math.max(v.scene,r.skip_scene or 0)+1 or v.scene
   r.strategy_key=key;r.skip_object=o;r.skip_scene=next_scene;r.skip_requested=false
   local s=guard.poll(o,next_scene,false,false)
   log('skip_guard_installed',key..'/threshold='..s.threshold..'/treat='..s.treat)
   status_ui.template(o.PressHoldWidget)
  end
  if r.skip_scene~=v.scene then
   guard.poll(o,r.skip_scene,false,false)
   if not controller.pending then controller.scene_segment(r.skip_scene)end
   return o
  end
  local authorize=v.phase==2 and tonumber(controller.snapshot.scene_exit)==1 and(not controller.cinema or controller.cinema.authorize_skip())
  local s=guard.poll(o,v.scene,v.phase==2,authorize)
  if s.consumed=='1'and r.skip_consumed_scene~=v.scene then r.skip_consumed_scene=v.scene;log('stock_skip_consumed','scene='..v.scene)end
  if v.phase==2 and s.requested=='1'and v.votes%2==0 and not controller.pending and not r.skip_requested then
   controller.vote_skip();r.skip_requested=true;log('host_skip_vote','scene='..v.scene)
  end
  return o
 end
 local function verify_loadout(widget)
  local result=native.command('inspect','hangar_loadout',widget)
  return result,result.status=='verified'and tonumber(result.selected)and tonumber(result.selected)>10 and result.value=='23010'
 end
 function r.start()
  assert(not r.error and controller.view().can_start_flight,'Нужны обе новые готовности в ангаре.')
  local widget=native.find('LiveMenuHangarStandbyWidget');assert(widget,'Нет штатного ангара.')
  local result,ok=verify_loadout(widget);assert(ok and math.floor(tonumber(result.selected)/1000)==tonumber(controller.snapshot.host_aircraft),'Изменилось оснащение перед вылетом.')
  controller.start_flight()
 end
 local hangar_steps={{'briefing_hangar','LiveMenuBriefingProgressWidget'},{'hangar_aircraft','LiveMenuHangarTopWidget'},{'host_manual','LiveMenuHangarSquadWidget'},{'squad_guest_aircraft','LiveMenuHangarSquadWidget'},{'aircraft_guest_f14','LiveMenuHangarAircraftSettingWidget'},{'squad_standby','LiveMenuHangarSquadWidget'}}
 local function flight_loaded()
  local result
  for _,o in ipairs(FindAllOf('LivePlayerController')or{})do if valid(o)and valid(o.Pawn)and o.Pawn:IsA('/Script/Live.LivePlayerPlane')then
   local world=o:GetWorld()
   if valid(world)and world:GetFullName():find('Mission007',1,true)and o.Pawn:GetClass():GetFullName():find(string.format('/PP%04d_',tonumber(controller.snapshot.host_aircraft)),1,true)then assert(not result,'Несколько миров хоста.');result=o end
  end end
  return result
 end
 local function save()
  local f=assert(io.open(output..'/mission-sync-adapter.tsv','w'));f:write('phase\t',r.phase,'\nstep\t',r.step,'\nerror\t',r.error or'','\n');f:close()
 end
 local function update()
  local v=controller.view()
  if v.phase~=0 and v.phase~=8 and not v.connected then r.phase='waiting_fresh_host_state';return end
  if v.phase>=1 and v.phase<=6 then assert(controller.snapshot.mission=='6'and controller.snapshot.difficulty=='1'and controller.snapshot.guest_aircraft=='23','Неподдерживаемая игровая конфигурация.')end
  if v.phase==1 then
   r.phase='loading_intro'
   if not r.menu_closed then if _G.AC8MainMenuEntry then _G.AC8MainMenuEntry.close()end;r.menu_closed=true end
   local step=steps[r.step]
   if step then
    if native.step(step[1],step[2])then log('sync_route_step',step[1]);r.step=r.step+1 end
   else
    local skip=protect_skip(v)
    if controller.cinema then
     controller.cinema.update();if controller.cinema.error then hold_world();error(controller.cinema.error)end
     if controller.cinema.handle then hold_world()end
     if controller.cinema.ready and(tonumber(controller.snapshot.cinema_prepared)or 0)%2==1 and not controller.pending and not r.intro_reported then controller.loaded();r.intro_reported=true end
     return
    end
    for _,o in ipairs(FindAllOf('LiveCinematicsLevelSequencePlayer')or{})do
     if valid(o)and o:IsPlaying()then
      local key=o:GetFullName()
      if not r.scene_players[key]then
       o:Pause();assert(o:IsPaused(),'Не удалось удержать катсцену.');r.scene_players[key]=o
       log('intro_player_held',key)
      end
     end
    end
    if skip or next(r.scene_players)then
     hold_world()
     if not controller.pending and not r.intro_reported then controller.loaded();r.intro_reported=true;log('host_intro_loaded','real scene held')end
    end
   end
  elseif v.phase==2 then
   r.phase='cutscene'
   if controller.cinema then
    controller.cinema.update();if controller.cinema.error then hold_world();error(controller.cinema.error)end
    if controller.cinema.playing then release_world()else hold_world()end
   end
   if not controller.cinema and not r.intro_released then
    release_world()
    for _,o in pairs(r.scene_players)do if valid(o)then o:Play()end end
    r.intro_released=true;log('host_intro_release','tick='..controller.now)
   end
   local skip=protect_skip(v)
   local flight=tonumber(controller.snapshot.scene_return)==6 and flight_loaded()
   local ended
   if tonumber(controller.snapshot.scene_return)==6 then ended=flight and flight.Pawn.bIsActivated==true and flight.Pawn.bIsIGCActor==false
   elseif r.hangar_movie then ended=native.find('LiveMenuHangarTopWidget')or native.find('LiveMenuHangarSquadWidget')or native.find('LiveMenuHangarAircraftSettingWidget')
   else ended=native.find('LiveMenuBriefingProgressWidget')end
   if not skip and ended and(not controller.cinema or controller.cinema.can_end())and not controller.pending and r.scene_reported~=v.scene then
    controller.scene_ended();r.scene_reported=v.scene;log('scene_end_observed','scene='..v.scene)
   end
  elseif v.phase==3 then
   r.phase='opening_hangar';r.hangar_step=r.hangar_step or 1
   if controller.snapshot.hangar_scene_supported=='1'and strategy()then
    protect_skip(v)
    if not controller.pending then r.hangar_movie=true;r.strategy_key=nil;controller.flight_scene(v.scene+1)end
    return
   end
   local step=hangar_steps[r.hangar_step]
   if step and step[1]=='host_manual'then
    local widget=native.find(step[2]);if widget then
     local result=native.command('inspect','hangar_loadout',widget)
     if result.status=='verified'and tonumber(result.selected)and tonumber(result.selected)>10 and result.selected~='23010'then r.hangar_step=r.hangar_step+1 end
    end
   elseif step and step[1]=='squad_standby'and native.find('LiveMenuHangarStandbyWidget')then r.hangar_step=r.hangar_step+1
   elseif step then
    if native.step(step[1],step[2])then r.hangar_step=r.hangar_step+1;log('sync_route_step',step[1])end
   elseif not controller.pending and not r.hangar_reported then
    local widget=native.find('LiveMenuHangarStandbyWidget');if widget then
     if not r.ui then r.ui=ui_module.attach(widget,controller,controller.status,r.start)end;r.ui.refresh()
     local result,ok=verify_loadout(widget)
     if ok then controller.hangar_verified(math.floor(tonumber(result.selected)/1000),23);r.hangar_reported=true;log('host_hangar_loaded',result.selected..'/23010')end
    end
   end
  elseif v.phase==4 then
   r.hangar_movie=nil
   r.phase='hangar';local widget=native.find('LiveMenuHangarStandbyWidget')
   if controller.session_policy then
    if not widget then
     if not controller.pending and tonumber(controller.snapshot.ready_mask or'0')>0 then controller.invalidate_ready()end
     return
    end
    local result,ok=verify_loadout(widget)
    if not ok then
     if not controller.pending and tonumber(controller.snapshot.ready_mask or'0')>0 then controller.invalidate_ready()end
     return
    end
    local aircraft=math.floor(tonumber(result.selected)/1000)
    if aircraft~=tonumber(controller.snapshot.host_aircraft)then if not controller.pending then controller.host_loadout(aircraft)end;return end
    if r.ui and r.ui.widget and r.ui.widget:GetAddress()~=widget:GetAddress()then r.ui.close();r.ui=nil end
   end
   if widget then if not r.ui then r.ui=ui_module.attach(widget,controller,controller.status,r.start)end;r.ui.refresh()end
  elseif v.phase==5 then
   r.phase='loading_flight'
   if not r.sortie then
    local widget=native.find('LiveMenuHangarStandbyWidget')
    if widget then
     local _,ok=verify_loadout(widget);assert(ok,'Оснащение изменилось перед вылетом.');if r.ui then r.ui.close()end
     if native.step('sortie','LiveMenuHangarStandbyWidget')then r.sortie=true;log('stock_sortie_once','native handler')end
    end
   elseif flight_loaded()then
    protect_skip(v)
    hold_world()
    if not controller.pending and not r.flight_reported then controller.flight_verified();r.flight_reported=true;log('host_flight_loaded','Mission007/paused')end
   end
  elseif v.phase==6 then
   r.phase='flight'
   if not r.flight_released then release_world();r.flight_released=true;log('host_flight_release','tick='..controller.now)end
   local o=strategy()
   if o and r.flight_scene_key~=o:GetFullName()and not controller.pending then
    r.flight_scene_key=o:GetFullName();r.strategy_key=nil;controller.flight_scene(v.scene+1)
   end
  elseif v.phase==8 then r.phase='stopped';if controller.cinema then controller.cinema.stop('session_stopped')end;release_world()end
 end
 function r.update()
  if r.error then return end
  local ok,err=pcall(update);if not ok then r.error=tostring(err);r.phase='error';log('mission_sync_adapter_error',r.error)end
  local ui_ok,ui_error=pcall(status_ui.update);if not ui_ok then log('sync_status_ui_error',ui_error)end
  save()
 end
 return r
end
return M
