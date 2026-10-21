-- Developer-only call-site validation for the current native aircraft confirmation.
return function(output,stamp)
    local candidates={}
    for _,o in ipairs(FindAllOf('LiveMenuHangarAircraftSettingWidget')or{})do
        if o:IsValid()and o.Visibility==0 and o:GetClass():GetFullName()=='WidgetBlueprintGeneratedClass /Game/Blueprints/UI/Menu/Hangar/WBP_Menu_Hangar_AircraftSettings_000.WBP_Menu_Hangar_AircraftSettings_000_C'then candidates[#candidates+1]=o end
    end
    assert(#candidates==1,'Need one visible aircraft selection page')
    local o=candidates[1];local operation=stamp:find('confirm',1,true)and'confirm'or'inspect'
    local f=assert(io.open(output..'/menu-route-request.tsv','w'))
    f:write('format\tac8-menu-route-v1\nstamp\t',stamp,'\ncreated_unix\t',os.time(),'\nobject\t',string.format('0x%x',o:GetAddress()),'\noperation\t',operation,'\nkind\taircraft_f14\n');f:close()
    local extension=assert(os.getenv('AC8_COOP_RECON_EXTENSION'))
    local root=assert(extension:match('^(.*)[/\\][^/\\]+$'))
    local call=assert(package.loadlib(root..'/../../../ac8_menu_route_r9b.dll','luaopen_ac8_menu_route'))
    call()
end
