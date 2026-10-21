-- Read strings as bounded FString data in native code; never reinterpret as FName.
return function(output,stamp)
    local extension=assert(os.getenv('AC8_COOP_RECON_EXTENSION'))
    local root=assert(extension:match('^(.*)[/\\][^/\\]+$'))
    local call=assert(package.loadlib(root..'/../../../ac8_menu_route_r9c.dll','luaopen_ac8_menu_route'))
    local objects=FindAllOf('LiveMenuBase')or{};assert(#objects<=64,'Menu budget exceeded')
    for _,o in ipairs(objects)do
        if o:IsValid()and o.Visibility==0 and o:IsA('/Script/Live.LiveMenuGenericBaseWidget')then
            local name=o:GetClass():GetFName():ToString():gsub('[^%w_]','')
            local ticket=stamp..'-'..name
            ticket=ticket:sub(1,64)
            local f=assert(io.open(output..'/menu-route-request.tsv','w'))
            f:write('format\tac8-menu-route-v1\nstamp\t',ticket,'\ncreated_unix\t',os.time(),'\nobject\t',string.format('0x%x',o:GetAddress()),'\noperation\tinspect\nkind\tinventory\n');f:close()
            call()
            local verified=false
            for _,file in ipairs({'menu-route-status.tsv','menu-route-commands.tsv'})do
                local input=io.open(output..'/'..file,'r')
                if input then
                    local text=input:read(65537);input:close();assert(#text<=65536,'Inventory budget exceeded')
                    local current=text:match('stamp\t([^\r\n]+)')==ticket
                    if file=='menu-route-status.tsv'then verified=current and text:find('status\tverified',1,true)~=nil end
                    if current and(file=='menu-route-status.tsv'or verified)then
                        local saved=assert(io.open(output..'/'..name..'-'..stamp..'-'..file,'w'));saved:write(text);saved:close()
                    end
                end
            end
        end
    end
end
