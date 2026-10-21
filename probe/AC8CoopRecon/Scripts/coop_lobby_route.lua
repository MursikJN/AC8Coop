-- Only stock menu transitions, executed on the UE game thread after lobby commit.
local M={}
M.steps={
 {'main_campaign','LiveMenuMainTopWidget'},
 {'campaign_free_mission','LiveMenuCampaignTopWidget'},
 {'difficulty_pilot','LiveMenuCampaignFreeMissionDifficultyWidget'},
 {'mission6','LiveMenuCampaignFreeMissionWidget'},
 {'narrative','LiveMenuCampaignNarrativeSelectWidget'},
 {'briefing_hangar','LiveMenuBriefingProgressWidget'},
 {'hangar_aircraft','LiveMenuHangarTopWidget'},
 {'aircraft_f14','LiveMenuHangarAircraftSettingWidget'},
 {'weapon1_default','LiveMenuHangarWeaponSetting1Widget'},
 {'weapon2_none','LiveMenuHangarWeaponSetting2Widget'},
 {'squad_standby','LiveMenuHangarSquadWidget'},
 {'sortie','LiveMenuHangarStandbyWidget'},
}
function M.new(api)
 local r={phase='idle',step=1};local attempted=false;local started;local selected={};local confirmed={}
 function r.supported(mission,plane)
  return mission==7 and plane==23 and (attempted or api.capable()==true)
 end
 function r.begin(mission,plane,id)
  assert(not attempted and r.supported(mission,plane),'Маршрут задания 6 / F-14D недоступен или уже запущен.')
  assert(type(id)=='number'and id>0 and id%1==0,'Неверный запуск.')
  attempted=true;started=api.now();r.phase='loading';r.launch=id;api.close();api.log('route_begin',id)
 end
 function r.update()
  if r.phase~='loading'then return end
  assert(api.now()-started<=600,'Превышено время штатной загрузки задания.')
  if api.flight_supported()then
   assert(r.step>#M.steps,'Полёт начался до подтверждения всех шагов маршрута.')
   r.phase='flight';api.log('route_flight_verified','Mission007/F14D');return
  end
  local step=M.steps[r.step];if not step then return end
  local object=api.find(step[2]);if not object then return end
  local result=api.command('inspect',step[1],object)
  if result.reason=='widget_or_selection_contract'then return end -- native animation/loading; no mutation
  assert(result.status=='verified','Проверка меню отклонена: '..tostring(result.reason))
  if result.reason=='target_available'then
   assert(not selected[r.step],'Выбор меню изменился после автоматического выбора.')
   selected[r.step]=true
   local changed=api.command('select',step[1],object)
   assert(changed.status=='selected','Не удалось выбрать пункт: '..tostring(changed.reason))
   -- No frame boundary here: native hover would otherwise replace the selection.
   result=api.command('inspect',step[1],object)
   assert(result.status=='verified'and result.reason=='target_selected','Выбор изменился до подтверждения.')
  end
  assert(result.reason=='target_selected','Неожиданный ответ проверки меню.')
  assert(not confirmed[r.step],'Повторное подтверждение меню запрещено.')
  confirmed[r.step]=true
  local answer=api.command('confirm',step[1],object)
  assert(answer.status=='returned'and answer.returned=='1','Меню отклонило переход: '..tostring(answer.reason))
  api.log('route_confirm',step[1]);r.step=r.step+1
 end
 return r
end
function M.game(base,output)
 local dll=assert(os.getenv('AC8_COOP_MENU_ROUTE_DLL'),'Отсутствует модуль штатного меню.')
 local call=assert(package.loadlib(dll,'luaopen_ac8_menu_route'))
 local sequence=0
 local function find(query)
  local found
  for _,o in ipairs(FindAllOf(query)or{})do
   if o:IsValid()and o.Visibility==0 then assert(not found,'Найдено несколько активных '..query);found=o end
  end
  return found and string.format('0x%x',found:GetAddress())or nil
 end
 local function command(operation,kind,object)
  sequence=sequence+1;assert(sequence<=10000,'Исчерпан журнал меню.')
  local stamp='route-'..os.time()..'-'..sequence
  local text='format\tac8-menu-route-v1\nstamp\t'..stamp..'\ncreated_unix\t'..os.time()..'\nobject\t'..object..'\noperation\t'..operation..'\nkind\t'..kind..'\n'
  local f=assert(io.open(output..'/menu-route-request.tsv','w'));assert(f:write(text));f:close();call()
  f=assert(io.open(output..'/menu-route-status.tsv','r'));local reply=f:read(2049);f:close();assert(#reply<=2048,'Ответ меню слишком велик.')
  local result={};for k,v in reply:gmatch('([^\r\n\t]+)\t([^\r\n]*)')do assert(not result[k],'Повтор поля меню.');result[k]=v end
  assert(result.format=='ac8-menu-route-v1'and result.stamp==stamp,'Получен чужой или устаревший ответ меню.')
  if operation~='inspect'or result.status~='verified'then
   f=assert(io.open(output..'/'..stamp..'-'..operation..'.tsv','w'));f:write(text,'\n',reply);f:close()
  end
  return result
 end
 local cached=false
 local api={now=base.now,log=base.log,find=find,command=command,flight_supported=base.flight_supported}
 function api.capable()
  if os.getenv('AC8_COOP_LOBBY')~='25201480'then return false end
  local main=find('LiveMenuMainTopWidget');if not main then return false end
  if not cached then local result=command('inspect','main_campaign',main);cached=result.status=='verified'end
  return cached
 end
 function api.close()if _G.AC8MainMenuEntry then _G.AC8MainMenuEntry.close()end end
 return M.new(api)
end
return M
