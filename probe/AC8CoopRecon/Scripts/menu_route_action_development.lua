-- Explicit developer job for one whitelisted native command; no automatic retries.
return function(output,stamp)
    local kind,query
    if stamp:find('sortie',1,true)then kind='sortie';query='LiveMenuHangarStandbyWidget'
    elseif stamp:find('squad',1,true)then kind='squad_standby';query='LiveMenuHangarSquadWidget'
    elseif stamp:find('hangar',1,true)then kind='hangar_aircraft';query='LiveMenuHangarTopWidget'
    elseif stamp:find('briefing',1,true)then kind='briefing_hangar';query='LiveMenuBriefingProgressWidget'
    elseif stamp:find('narrative',1,true)then kind='narrative';query='LiveMenuCampaignNarrativeSelectWidget'
    elseif stamp:find('mission6',1,true)then kind='mission6';query='LiveMenuCampaignFreeMissionWidget'
    elseif stamp:find('difficulty',1,true)then kind='difficulty_pilot';query='LiveMenuCampaignFreeMissionDifficultyWidget'
    elseif stamp:find('main',1,true)then kind='main_campaign';query='LiveMenuMainTopWidget'
    elseif stamp:find('campaign',1,true)then kind='campaign_free_mission';query='LiveMenuCampaignTopWidget'
    elseif stamp:find('weapon2',1,true)then kind='weapon2_none';query='LiveMenuHangarWeaponSetting2Widget'
    elseif stamp:find('weapon',1,true)then kind='weapon1_default';query='LiveMenuHangarWeaponSetting1Widget'
    else kind='aircraft_f14';query='LiveMenuHangarAircraftSettingWidget'end
    local operation=stamp:find('confirm',1,true)and'confirm'or(stamp:find('select',1,true)and'select'or'inspect')
    local objects={};for _,o in ipairs(FindAllOf(query)or{})do if o:IsValid()and o.Visibility==0 then objects[#objects+1]=o end end
    assert(#objects==1,'Need one visible '..query)
    local o=objects[1];local extension=assert(os.getenv('AC8_COOP_RECON_EXTENSION'));local root=assert(extension:match('^(.*)[/\\][^/\\]+$'))
    local f=assert(io.open(output..'/menu-route-request.tsv','w'))
    f:write('format\tac8-menu-route-v1\nstamp\t',stamp,'\ncreated_unix\t',os.time(),'\nobject\t',string.format('0x%x',o:GetAddress()),'\noperation\t',operation,'\nkind\t',kind,'\n');f:close()
    assert(package.loadlib(root..'/../../../ac8_menu_route_r9p.dll','luaopen_ac8_menu_route'))()
    local input=assert(io.open(output..'/menu-route-status.tsv','r'));local text=input:read('*a');input:close()
    local saved=assert(io.open(output..'/menu-route-result-'..stamp..'.tsv','w'));saved:write(text);saved:close()
end
