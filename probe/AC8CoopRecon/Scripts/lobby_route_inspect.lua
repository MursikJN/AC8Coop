-- Explicit developer snapshot: reflected metadata only, no game/menu commands.
return function(output,stamp)
    local f=assert(io.open(output..'/lobby-route-'..stamp..'.tsv','w'))
    local function row(...)local a={...};for i,v in ipairs(a)do a[i]=tostring(v):gsub('[\r\n\t]',' '):sub(1,2048)end;f:write(table.concat(a,'\t'),'\n')end
    local seen={}
    local function valid(o)return o and o:IsValid()end
    local function name(o)return valid(o)and o:GetFullName()or'invalid'end
    local function schema(c)
        for _=1,20 do
            if not valid(c)or seen[name(c)]then return end
            seen[name(c)]=true;local cn=name(c);row('class',cn,'super',name(c:GetSuperStruct()))
            c:ForEachProperty(function(p)
                local t=p:GetClass():GetFName():ToString();local extra=''
                if t=='StructProperty'then pcall(function()extra=name(p:GetStruct())end)end
                row('property',cn,p:GetFName():ToString(),t,p:GetOffset_Internal(),extra)
                if t=='StructProperty'then pcall(function()schema(p:GetStruct())end)end
            end)
            c:ForEachFunction(function(fn)
                local n=fn:GetFName():ToString();row('function',cn,n,fn:GetFunctionFlags())
                fn:ForEachProperty(function(p)
                    local extra='';pcall(function()extra=name(p:GetStruct())end)
                    row('parameter',cn,n,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal(),extra)
                end)
            end)
            c=c:GetSuperStruct()
        end
    end
    local ok,err=pcall(function()
        for _,path in ipairs({'/Script/Live.LiveBlueprintLibrary','/Script/Live.LiveNUIFunctionLibrary','/Script/Live.LiveLinkBlueprintLibrary','/Script/Live.LiveHangarGameModeInterface','/Script/Live.LiveCampaignMissionConfig','/Script/Live.LiveMenuHangarSortieWidget'})do
            local c=StaticFindObject(path);if valid(c)then schema(c)end
        end
        for _,class in ipairs({'LiveMenuMainTopWidget','LiveMenuCampaignTopWidget','LiveMenuHangarAircraftSettingWidget','LiveMenuHangarStandbyWidget','LiveMenuHangarSortieWidget','LiveMenuGenericBaseWidget','LiveMenuBase','LiveMenuCommandListWidget','LiveMenuCommandWidget','LiveNUIUserWidget'})do
            local o=StaticFindObject('/Script/Live.Default__'..class)
            if valid(o)then row('address',name(o),string.format('0x%x',o:GetAddress()))end
        end
        for _,query in ipairs({'LiveGameInstance','LiveMenuMainTopWidget','LiveMenuBase','LiveNUIRootUserWidget','LiveNUICommonDialogWidget','LiveNUICampaignTutorialDialogContentsWidget','LivePlayerController','GameModeBase','GameStateBase','LiveHangarManager'})do
            local objects=FindAllOf(query)or{};row('query',query,#objects)
            for i,o in ipairs(objects)do
                if i>16 then break end
                if valid(o)then
                    row('instance',query,name(o));row('address',name(o),string.format('0x%x',o:GetAddress()));schema(o:GetClass())
                    local c=o:GetClass()
                    for _=1,16 do
                        if not valid(c)then break end
                        c:ForEachProperty(function(p)
                            local n=p:GetFName():ToString();local t=p:GetClass():GetFName():ToString()
                            pcall(function()
                                if t=='ObjectProperty'then local v=o[n];row('reference',name(o),n,name(v));if valid(v)then row('address',name(v),string.format('0x%x',v:GetAddress()));schema(v:GetClass())end
                                elseif t=='IntProperty'or t=='BoolProperty'or t=='EnumProperty'or t=='ByteProperty'then row('value',name(o),n,o[n])end
                            end)
                        end)
                        c=c:GetSuperStruct()
                    end
                end
            end
        end
    end)
    row('summary',ok,err or'');f:close()
end
