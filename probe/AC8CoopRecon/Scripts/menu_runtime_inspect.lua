-- Read-only UMG/main-menu structure and reflected function signatures.
return function(output, stamp)
    local f=assert(io.open(output..'/menu-structure-'..stamp..'.tsv','w'))
    local function clean(x)return tostring(x):gsub('[\r\n\t]',' '):sub(1,3000)end
    local function row(...)local t={...};for i,v in ipairs(t)do t[i]=clean(v)end;f:write(table.concat(t,'\t'),'\n')end
    local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v end
    local function name(o)return valid(o) and o:GetFullName() or 'invalid'end
    local seen,classes={},{}
    local count=0
    local inspect
    local function schema(c)
        for _=1,18 do
            if not valid(c)or classes[name(c)]then break end
            local cn=name(c);classes[cn]=true
            row('class',cn,'super',name(c:GetSuperStruct()))
            c:ForEachProperty(function(p)
                row('property',cn,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal())
            end)
            c:ForEachFunction(function(fn)
                local fnn=fn:GetFName():ToString();row('function',cn,fnn,fn:GetFunctionFlags())
                fn:ForEachProperty(function(p)
                    local detail='';local typ=p:GetClass():GetFName():ToString()
                    if typ=='StructProperty'then pcall(function()detail=name(p:GetStruct())end)end
                    if typ=='ObjectProperty'or typ=='ClassProperty'then pcall(function()detail=name(p:GetPropertyClass())end)end
                    row('parameter',cn,fnn,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal(),detail)
                end)
            end)
            c=c:GetSuperStruct()
        end
    end
    inspect=function(o,depth,via)
        if depth>12 or not valid(o)or count>=400 then return end
        local n=name(o);if seen[n]then return end;seen[n]=true;count=count+1
        row('object',n,'via',via);schema(o:GetClass())
        for _,key in ipairs({'Visibility','bIsEnabled','Text','WidgetTree','RootWidget','CommandList','RootPageSettingsData','WBP_MenuCommon_MainList_000'})do
            pcall(function()
                local v=o[key]
                if type(v)=='string'or type(v)=='number'or type(v)=='boolean'then row('value',n,key,v)
                elseif key=='Text'and v then row('value',n,key,v:ToString())
                elseif key~='Visibility'and key~='bIsEnabled'and valid(v)then row('reference',n,key,name(v));inspect(v,depth+1,key)
                end
            end)
        end
        pcall(function()row('viewport',n,o:IsInViewport())end)
        pcall(function()row('parent',n,name(o:GetParent()))end)
        -- UPanelWidget getter only, bounded before reading each child.
        if o:IsA('/Script/UMG.PanelWidget')then
            local total=o:GetChildrenCount();row('children',n,total)
            for i=0,math.min(total,80)-1 do inspect(o:GetChildAt(i),depth+1,'child '..i)end
        end
    end
    local ok,err=pcall(function()
        for _,o in ipairs(FindAllOf('LiveMenuMainTopWidget')or{})do
            if valid(o)and name(o):find('WBP_Menu_MainTop',1,true)and not name(o):find('Default__',1,true)then inspect(o,0,'main menu')end
        end
        for _,path in ipairs({'/Script/UMG.WidgetBlueprintLibrary','/Script/UMG.Button','/Script/UMG.VerticalBox','/Script/UMG.TextBlock','/Script/UMG.EditableTextBox','/Script/UMG.ComboBoxString','/Script/UMG.WidgetTree'})do
            local c=StaticFindObject(path);if valid(c)then schema(c)end
        end
    end)
    row('summary','objects',count,'ok',ok,'error',err or'');f:close()
    print('[AC8Menu] structure saved '..stamp..' objects='..count..'\n')
end
