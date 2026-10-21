-- One real host world and an external guest simulator. All menu work stays on the game thread.
local M={}
M.steps={
 {'main_campaign','LiveMenuMainTopWidget'}, {'campaign_free_mission','LiveMenuCampaignTopWidget'},
 {'difficulty_pilot','LiveMenuCampaignFreeMissionDifficultyWidget'}, {'mission6','LiveMenuCampaignFreeMissionWidget'},
 {'narrative','LiveMenuCampaignNarrativeSelectWidget'}, {'briefing_hangar','LiveMenuBriefingProgressWidget'},
 {'hangar_aircraft','LiveMenuHangarTopWidget'}, {'host_manual','LiveMenuHangarSquadWidget'},
 {'squad_guest_aircraft','LiveMenuHangarSquadWidget'}, {'aircraft_guest_f14','LiveMenuHangarAircraftSettingWidget'},
 {'squad_standby','LiveMenuHangarSquadWidget'},
}
function M.new(controller,output,source,log)
 local native=assert(loadfile(source..'/local_menu_native.lua'))().new(output)
 local ui_module=assert(loadfile(source..'/local_hangar_ui.lua'))()
 local r={step=1,started=nil,phase='idle',error=nil,sortie=false,hangar_reported=false,flight_reported=false,ui=nil}
 local function save()
  local f=assert(io.open(output..'/hangar-adapter-status.tsv','w'))
  f:write('phase\t',r.phase,'\nstep\t',r.step,'\nerror\t',r.error or'','\ndetail\t',r.detail or'','\nslot\t1\nguest_aircraft\t23\n');f:close()
 end
 local function map_verified(widget)
  local state=controller.snapshot
  if state.mission~='6'or state.difficulty~='1'or state.guest_aircraft~='23'then return false end
  local result=native.command('inspect','hangar_loadout',widget)
  return result.status=='verified'and tonumber(result.selected)==(tonumber(state.host_aircraft)or 0)*1000+10 and result.value=='23010'
 end
 function r.start()
  assert(not r.error and controller.view().can_start_flight,'Нужны обе готовности в ангаре.')
  local widget=native.find('LiveMenuHangarStandbyWidget');assert(widget and map_verified(widget),'Самолёт хоста и F-14D ведомого не подтверждены в штатном ангаре.')
  controller.start_flight()
 end
 local function flight_loaded()
  local count=0
  for _,pc in ipairs(FindAllOf('LivePlayerController')or{})do if pc:IsValid()then
   local pawn=pc.Pawn;local world=pc:GetWorld()
   if pawn and pawn:IsValid()and pawn:IsA('/Script/Live.LivePlayerPlane')then
    if not world:IsValid()or not world:GetFullName():find('Mission007',1,true)or not pawn:GetClass():GetFullName():find(string.format('/PP%04d_',tonumber(controller.snapshot.host_aircraft)),1,true)then return false end
    count=count+1
   end
  end end
  return count==1
 end
 local function update()
  local state=controller.snapshot;local phase=tonumber(state.phase)
  if phase==3 then
   if not r.started then
    assert(state.mission=='6'and state.difficulty=='1'and state.guest_aircraft=='23','Неподдерживаемая конфигурация.')
    r.started=os.time();r.phase='opening_hangar'
    if _G.AC8MainMenuEntry then _G.AC8MainMenuEntry.close()end
    log('hangar_route_begin','mission6/Easy/hostManual/wingman1F14D')
   end
   if r.step<=7 then assert(os.time()-r.started<600,'Превышено время открытия ангара.')end
   local step=M.steps[r.step]
   if step and step[1]=='host_manual'then
    r.phase='waiting_host_aircraft';r.detail='Хост: выберите свой самолёт и вооружение, затем перейдите к составу звена.'
    local squad=native.find('LiveMenuHangarSquadWidget')
    if squad then
     local result=native.command('inspect','hangar_loadout',squad)
     if result.status=='verified'then
      assert(tonumber(result.selected)and tonumber(result.selected)>10,'Самолёт хоста не выбран.')
      if result.selected=='23010'then
       r.detail='Оставьте F-14D гостю: вернитесь к выбору самолёта хоста и выберите другой.'
      else r.step=r.step+1 end
     end
    end
   elseif step and step[1]=='squad_standby'and native.find('LiveMenuHangarStandbyWidget')then
    r.step=r.step+1;log('hangar_route_step','standby_already_open')
   elseif step then
    if step[1]=='squad_standby'and native.find('LiveMenuHangarAircraftSettingWidget')then
     r.phase='waiting_host_wingmen';r.detail='Хост: завершите штатный выбор самолётов двух остальных ведомых.'
    end
    if native.step(step[1],step[2])then log('hangar_route_step',step[1]);r.step=r.step+1 end
   elseif not r.hangar_reported then
    local widget=native.find('LiveMenuHangarStandbyWidget')
    if widget then
     local result=native.command('inspect','hangar_loadout',widget)
     if result.status~='verified'and result.reason=='hangar_loadout_contract'then
      -- A visible standby widget can still be entering state 5. Do not make
      -- this read-only transition failure permanently disable both players.
      r.verify_started=r.verify_started or os.time()
      assert(os.time()-r.verify_started<10,'Не удалось прочитать штатное оснащение: '..tostring(result.reason))
      r.phase='waiting_hangar_verification';r.detail='Ожидание завершения открытия экрана готовности.';return
     end
     assert(result.status=='verified','Не удалось прочитать штатное оснащение: '..tostring(result.reason))
     r.verify_started=nil
     assert(tonumber(result.selected)and tonumber(result.selected)>10 and result.value=='23010','Не подтверждены самолёт хоста и F-14D первого ведомого.')
     local host_plane=math.floor(tonumber(result.selected)/1000)
     if not controller.pending then controller.hangar_verified(host_plane,23);r.hangar_reported=true;log('hangar_loadout_verified','player='..result.selected..'/wingman1=23010')end
    end
   end
  elseif phase==4 then
   r.phase='hangar'
   local widget=native.find('LiveMenuHangarStandbyWidget')
   if widget then
    if not r.ui then r.ui=ui_module.attach(widget,controller,controller.status,r.start)end
    r.ui.refresh()
   end
  elseif phase==5 then
   r.phase='starting_mission'
   if not r.sortie then
    local widget=native.find('LiveMenuHangarStandbyWidget')
    if widget then
     assert(map_verified(widget),'Оснащение изменилось перед вылетом.')
     if r.ui then r.ui.close()end
     if native.step('sortie','LiveMenuHangarStandbyWidget')then r.sortie=true;log('host_sortie_confirmed','native stock handler')end
    end
   elseif flight_loaded()and not controller.pending and not r.flight_reported then
    controller.flight_verified();r.flight_reported=true;log('host_mission_verified','Mission007/host-selected-aircraft')
   end
  elseif phase==6 then r.phase='flight'
  elseif phase==8 then r.phase='stopped';return end
 end
 function r.update()
  if r.error then return end
  local ok,err=pcall(update)
  if not ok then r.error=tostring(err);r.phase='error';log('hangar_adapter_error',r.error)end
  save()
 end
 return r
end
return M
