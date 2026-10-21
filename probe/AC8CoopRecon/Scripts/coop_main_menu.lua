-- AC8 build 25201480. Attach to the existing MainTop widget tree, never AddToViewport.
local M={}
local stock_font=nil
local widget_suffix=''
local function valid(o)return o and o:IsValid()end
local function construct(path,outer,name)
    local class=StaticFindObject(path);assert(valid(class),'Missing class '..path)
    local obj=StaticConstructObject(class,outer,FName(name..widget_suffix));assert(valid(obj),'Cannot construct '..name);return obj
end
local function text(outer,name,caption,size)
    local t=construct('/Script/UMG.TextBlock',outer,name)
    if stock_font then t:SetFont(stock_font)end
    t.Font.Size=size or 30
    t:SetText(FText(caption));t:SetColorAndOpacity({SpecifiedColor={R=.88,G=.92,B=.98,A=1},ColorUseRule=0})
    return t
end
local function button(outer,name,caption,size)
    local b=construct('/Script/UMG.Button',outer,name)
    local t=text(outer,name..'_Text',caption,size);local child=b:AddChild(t)
    child:SetHorizontalAlignment(1);child:SetPadding({Left=10,Top=3,Right=25,Bottom=3})
    b:SetBackgroundColor({R=1,G=1,B=1,A=0})
    return b,t
end
local function check_function(path,fields)
    local f=StaticFindObject(path);assert(valid(f),'Missing UI function '..path)
    local actual={};f:ForEachProperty(function(p)actual[#actual+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()end)
    assert(table.concat(actual,',')==fields,'Changed UI signature '..path)
end
function M.attach(options)
    if _G.AC8MainMenuEntry and valid(_G.AC8MainMenuEntry.main)then return _G.AC8MainMenuEntry end
    widget_suffix=options.widget_suffix or''
    check_function('/Script/UMG.GridPanel:AddChildToGrid','Content:ObjectProperty,InRow:IntProperty,InColumn:IntProperty,ReturnValue:ObjectProperty')
    check_function('/Script/UMG.TextBlock:SetText','InText:TextProperty')
    check_function('/Script/UMG.Button:IsPressed','ReturnValue:BoolProperty')
    local main
    for _,candidate in ipairs(FindAllOf('LiveMenuMainTopWidget')or{})do
        if valid(candidate)and candidate:GetClass():GetFullName()=='WidgetBlueprintGeneratedClass /Game/Blueprints/UI/Menu/Main/WBP_Menu_MainTop_000.WBP_Menu_MainTop_000_C'then
            assert(not main,'Ambiguous MainTop');main=candidate
        end
    end
    if not main then return nil end
    local list=main.CommandList;assert(valid(list),'Main command list missing')
    local reference=list.WBP_Menu_Text_Focus_000_06;assert(valid(reference),'Original Exit row missing')
    local grid=reference:GetParent();assert(valid(grid)and grid:IsA('/Script/UMG.GridPanel'),'Main list parent changed')
    assert(grid:GetFullName():match('%.GridPanelMain$'),'Unexpected main grid')
    local seventh=list.WBP_Menu_Text_Focus_000_07;assert(valid(seventh),'Reserved main row missing')
    if seventh.Visibility~=1 then return nil end -- wait for the stock command-list initialization/animation
    local tree=main.WidgetTree;assert(valid(tree),'Main WidgetTree missing')
    -- StaticConstructObject must never reconstruct an existing widget that
    -- Slate may still reference after RemoveFromParent. Name every attachment
    -- distinctly, including diagnostic reloads in the same WidgetTree.
    if options.widget_suffix==nil then
        _G.AC8MenuWidgetSerial=(_G.AC8MenuWidgetSerial or 0)+1
        widget_suffix='_AC8UI'.._G.AC8MenuWidgetSerial
    end
    local inspected=0
    local function font_from(widget,depth)
        if stock_font or not valid(widget)or depth>12 or inspected>=64 then return end;inspected=inspected+1
        if widget:IsA('/Script/UMG.TextBlock')then
            local caption=widget:GetText():ToString();if caption~=''and caption~='(SAMPLE)'then stock_font=widget.Font end
        elseif widget:IsA('/Script/UMG.UserWidget')then font_from(widget.WidgetTree.RootWidget,depth+1)
        elseif widget:IsA('/Script/UMG.PanelWidget')then for i=0,math.min(widget:GetChildrenCount(),32)-1 do font_from(widget:GetChildAt(i),depth+1)end end
    end
    stock_font=nil;font_from(reference,0)
    local entry,label=button(tree,'AC8_Coop_Entry','СОВМЕСТНАЯ ИГРА',37)
    local state={main=main,list=list,grid=grid,entry=entry,label=label,controls={},open=false,options=options,original_visibility=grid.Visibility}
    _G.AC8MainMenuEntry=state -- only own objects, rooted until the original main widget is destroyed
    if not _G.AC8MainMenuMouseBound then
        _G.AC8MainMenuMouseBound=true
        _G.AC8MainMenuClickSerial=0
        RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,function()
            _G.AC8MainMenuClickSerial=_G.AC8MainMenuClickSerial+1
        end)
    end
    state.last_click=_G.AC8MainMenuClickSerial
    local ok,err=pcall(function()
        local slot=grid:AddChildToGrid(entry,7,0);assert(valid(slot),'Menu button was not attached')
        slot:SetPadding({Left=0,Top=4,Right=8,Bottom=4})
        slot:SetHorizontalAlignment(0)
        main:ForceLayoutPrepass()
    end)
    if not ok then pcall(function()entry:RemoveFromParent()end);_G.AC8MainMenuEntry=nil;error(err)end
    function state.close()
        state.open=false;state.ui_error=nil
        if state.compact then state.compact.close()end
        if state.page and valid(state.page)then state.page:SetVisibility(2)end
        if valid(state.grid)then state.grid:SetVisibility(state.original_visibility)end
        if state.input_player and valid(state.input_player)then
            state.input_library:SetInputMode_GameAndUIEx(state.input_player,state.entry,0,false,true)
            state.input_player.bShowMouseCursor=state.original_cursor
            state.input_player=nil
        end
    end
    local function content_button(box,name,caption,fn)
        local b,t=button(tree,name,caption,27);local slot=box:AddChildToVerticalBox(b)
        slot:SetPadding({Left=0,Top=5,Right=0,Bottom=5})
        state.controls[#state.controls+1]={widget=b,label=t,action=fn,was_pressed=false}
        return b,t
    end
    function state.show()
        if state.open then return end
        if options.compact and not state.page then
            local count=#state.controls
            local built,result=pcall(function()return assert(loadfile(options.source..'/coop_lobby_layout.lua'))().build(state,options,{construct=construct,text=text,button=button})end)
            if not built then
                if state.page and valid(state.page)then state.page:RemoveFromParent()end;state.page=nil
                for i=#state.controls,count+1,-1 do table.remove(state.controls,i)end
                state.build_attempt=(state.build_attempt or 0)+1;widget_suffix=widget_suffix..'_Retry'..state.build_attempt
                error(result)
            end
            state.compact=result
        end
        if not state.page then
            local parent=grid:GetParent();assert(parent:IsA('/Script/UMG.CanvasPanel'),'Main content parent changed')
            local page=construct('/Script/UMG.VerticalBox',tree,'AC8_Coop_Page');state.page=page
            local slot=parent:AddChildToCanvas(page)
            local anchors=grid.Slot:GetAnchors();local alignment=grid.Slot:GetAlignment()
            slot:SetAnchors({Minimum={X=anchors.Minimum.X,Y=anchors.Minimum.Y},Maximum={X=anchors.Maximum.X,Y=anchors.Maximum.Y}})
            slot:SetAlignment({X=alignment.X,Y=alignment.Y})
            local position=grid.Slot:GetPosition();local spacer=grid:GetChildAt(0)
            assert(spacer:IsA('/Script/UMG.Spacer'),'Main list top spacing changed')
            local top=spacer.Size.Y;assert(type(top)=='number'and top>=0 and top<=600,'Main list spacing invalid')
            slot:SetPosition({X=position.X+75,Y=position.Y+top});slot:SetSize({X=1100,Y=760})
            page:AddChildToVerticalBox(text(tree,'AC8_Coop_Title','СОВМЕСТНАЯ ИГРА',37))
            state.choice=text(tree,'AC8_Coop_Choice',options.local_session and 'Локальный тест: '..(options.is_host and 'ХОСТ' or 'ГОСТЬ')or'Задание: 6     Самолёт: F-14D',29)
            page:AddChildToVerticalBox(state.choice)
            local hint=text(tree,'AC8_Coop_Hint',options.local_session and(options.hangar_adapter and'Первый маршрут: задание 6 · ПИЛОТ · F-14D. После ангара нужна новая готовность.'or'Проверка лобби на одном ПК. Запуск миссии пока недоступен.')or(options.continuous and 'Самолёт друга виден до выхода, потери связи или F9.'or'Одинаковое оснащение у обоих. Первый опыт: до 15 секунд.'),23)
            hint:SetAutoWrapText(true);page:AddChildToVerticalBox(hint)
            if options.local_session then
                if options.is_host then
                    page:AddChildToVerticalBox(text(tree,'AC8_Local_MissionLabel','Номер задания:',23))
                    state.mission=construct('/Script/UMG.EditableTextBox',tree,'AC8_Local_Mission')
                    state.mission.Font.Size=25;state.mission:SetText(FText(options.hangar_adapter and'6'or'1'));page:AddChildToVerticalBox(state.mission)
                    state.difficulty=construct('/Script/UMG.ComboBoxString',tree,'AC8_Local_Difficulty');state.difficulty.Font.Size=25
                    for _,caption in ipairs({'ПИЛОТ','ВЕТЕРАН','ЭЛИТА','НОВИЧОК (СЮЖЕТ)'})do state.difficulty:AddOption(caption)end
                    state.difficulty:SetSelectedIndex(options.hangar_adapter and 0 or 1);page:AddChildToVerticalBox(state.difficulty)
                    content_button(page,'AC8_Local_Apply','Применить задание и сложность',function()
                        local raw=state.mission:GetText():ToString();assert(raw:match('^%d+$'),'Введите номер задания.')
                        local number=tonumber(raw);assert(number and number>=1 and number<=999,'Номер задания: 1–999.')
                        options.select(number,state.difficulty:GetSelectedIndex()+1)
                    end)
                    state.peer=state.mission
                else
                    state.peer=state.entry
                end
                state.ready_button,state.ready_text=content_button(page,'AC8_Local_Ready','Готов',options.ready)
                if options.hangar_adapter then
                    state.hangar_button=content_button(page,'AC8_Local_Hangar','Перейти в ангар',options.open_hangar)
                end
                state.status=text(tree,'AC8_Local_Status','Ожидание подключения…',24)
                state.status:SetAutoWrapText(true);page:AddChildToVerticalBox(state.status)
                content_button(page,'AC8_Local_Back','Назад',state.close)
            elseif options.simple then
                page:AddChildToVerticalBox(text(tree,'AC8_Coop_PeerLabel','SteamID64 друга:',25))
                local edit=construct('/Script/UMG.EditableTextBox',tree,'AC8_Coop_Peer')
                edit:SetHintText(FText('17 цифр'));edit.Font.Size=27;page:AddChildToVerticalBox(edit);state.peer=edit
                local function connect(role)
                    local peer=edit:GetText():ToString()
                    assert(#peer==17 and peer:match('^[1-9]%d+$'),'Введите SteamID64 друга: 17 цифр.')
                    options.configure(role,peer)
                end
                state.host_button=content_button(page,'AC8_Coop_Host','Создать лобби',function()connect('host')end)
                state.join_button=content_button(page,'AC8_Coop_Join','Присоединиться',function()connect('guest')end)
                state.status=text(tree,'AC8_Coop_Status','Введите SteamID64 друга и выберите действие.',24)
                state.status:SetAutoWrapText(true);page:AddChildToVerticalBox(state.status)
                state.ready_button,state.ready_text=content_button(page,'AC8_Coop_Ready','Готов',function()options.ready()end)
                state.launch_button=content_button(page,'AC8_Coop_Launch','Запустить задание 6 · F-14D',function()options.start()end)
                state.ready_button:SetVisibility(1);state.ready_button:SetIsEnabled(false)
                state.launch_button:SetVisibility(1);state.launch_button:SetIsEnabled(false)
                content_button(page,'AC8_Coop_Back','Назад',function()
                    if options.reset then options.reset()end
                    state.close()
                end)
                if options.restore then options.restore({SetSelectedIndex=function()end},edit)end
            else
            local role=construct('/Script/UMG.ComboBoxString',tree,'AC8_Coop_Role')
            role.Font.Size=27
            role:AddOption('Создать сессию');role:AddOption('Присоединиться');role:SetSelectedIndex(0)
            page:AddChildToVerticalBox(role);state.role=role
            state.host_button=content_button(page,'AC8_Coop_Host','Создать лобби',function()role:SetSelectedIndex(0)end)
            state.join_button=content_button(page,'AC8_Coop_Join','Присоединиться к другу',function()role:SetSelectedIndex(1)end)
            page:AddChildToVerticalBox(text(tree,'AC8_Coop_PeerLabel','SteamID64 второго участника:',25))
            local edit=construct('/Script/UMG.EditableTextBox',tree,'AC8_Coop_Peer')
            edit:SetHintText(FText('17 цифр'));edit.Font.Size=27;page:AddChildToVerticalBox(edit);state.peer=edit
            state.status=text(tree,'AC8_Coop_Status','Выберите роль, введите SteamID64 и подтвердите настройки.',24)
            state.status:SetAutoWrapText(true);page:AddChildToVerticalBox(state.status)
            state.configure_button=content_button(page,'AC8_Coop_Configure','Подтвердить настройки',function()
                if options.configure then options.configure(role:GetSelectedIndex()==0 and 'host'or'guest',edit:GetText():ToString())end
                state.host_button:SetIsEnabled(false);state.join_button:SetIsEnabled(false)
                role:SetIsEnabled(false);edit:SetIsReadOnly(true);state.configure_button:SetIsEnabled(false)
                state.ready_button:SetIsEnabled(true);state.stop_button:SetIsEnabled(true)
            end)
            state.ready_button=content_button(page,'AC8_Coop_Ready','Готов — автоматический старт',function()
                if options.ready then options.ready()end;if not options.lobby then state.ready_button:SetIsEnabled(false)end
            end)
            if options.lobby then
                state.ready_text=state.controls[#state.controls].label
                state.ready_text:SetText(FText('Готов'))
                state.launch_button=content_button(page,'AC8_Coop_Launch','Запустить задание 6 · F-14D',function()if options.start then options.start()end end)
                state.launch_button:SetIsEnabled(false)
            end
            state.ready_button:SetIsEnabled(false)
            state.stop_button=content_button(page,'AC8_Coop_Stop','Остановить совместный опыт',function()if options.stop then options.stop()end end)
            state.stop_button:SetIsEnabled(false)
            content_button(page,'AC8_Coop_Report','Сохранить отладочный отчёт',function()if options.report then options.report()end end)
            content_button(page,'AC8_Coop_Back','Назад',state.close)
            if options.restore then options.restore(role,edit)end
            end
        end
        state.open=true;grid:SetVisibility(2);state.page:SetVisibility(0);main:ForceLayoutPrepass()
        if state.compact then state.compact.open()end
        local pc=require('UEHelpers').GetPlayerController()
        local library=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
        assert(valid(pc)and valid(library),'Menu input controller unavailable')
        state.input_player=pc;state.input_library=library;state.original_cursor=pc.bShowMouseCursor
        library:SetInputMode_UIOnlyEx(pc,state.peer,0,true);pc.bShowMouseCursor=true
        if options.open then options.open()end
    end
    function state.refresh()
        if _G.AC8MainMenuEntry~=state or not valid(main)or not valid(entry)then return false end
        -- Steam owns input while its selector is open. Do not replay its clicks
        -- against the lobby buttons after the overlay closes.
        if options.input_blocked and options.input_blocked()then
            state.last_click=_G.AC8MainMenuClickSerial;state.was_pressed=entry:IsPressed()
            for _,control in ipairs(state.controls)do control.was_pressed=control.widget:IsPressed()end
            return true
        end
        -- Same widget tree inherits main-menu visibility. Never show a viewport overlay in flight.
        if main.Visibility~=0 and main.Visibility~=4 then return true end
        local serial=_G.AC8MainMenuClickSerial;local mouse=serial~=state.last_click;state.last_click=serial
        local pressed=entry:IsPressed();local hovered=entry:IsHovered()
        entry:SetBackgroundColor({R=1,G=1,B=1,A=hovered and .92 or 0})
        label:SetColorAndOpacity({SpecifiedColor=hovered and{R=.045,G=.055,B=.065,A=1}or{R=.9,G=.93,B=.94,A=1},ColorUseRule=0})
        if not state.open and ((mouse and hovered)or(pressed and not state.was_pressed and not hovered))then
            state.show();state.was_pressed=pressed;return true
        end
        state.was_pressed=pressed
        if state.open then
            for _,control in ipairs(state.controls)do
                local down=control.widget:IsPressed()
                local hover=control.widget:IsHovered()
                if control.visible~=false and control.widget.bIsEnabled and ((mouse and hover)or(down and not control.was_pressed and not hover))then
                    local success,problem=pcall(control.action)
                    state.ui_error=not success and tostring(problem):gsub('^.-:%d+:%s*','')or nil
                    if not success and options.error then options.error(problem)end
                    control.was_pressed=down
                    break -- consume one click once, even when the page changes under the cursor
                end
                control.was_pressed=down
            end
            if state.compact then state.compact.refresh(state.ui_error)
            else
            if options.status then state.status:SetText(FText(state.ui_error or options.status()))end
            if options.local_session and options.view then
                local v=options.view()
                state.ready_button:SetIsEnabled(v.can_ready==true)
                state.ready_text:SetText(FText(v.ready and 'Снять готовность' or 'Готов'))
                state.choice:SetText(FText(v.choice))
                if state.hangar_button then state.hangar_button:SetIsEnabled(v.can_open_hangar==true)end
            elseif options.lobby and options.view then
                local v=options.view()
                if options.simple then
                    local idle=v.phase=='idle'
                    state.peer:SetIsReadOnly(not idle)
                    state.host_button:SetVisibility(idle and 0 or 1)
                    state.join_button:SetVisibility(idle and 0 or 1)
                    state.ready_button:SetVisibility(v.phase=='room'and 0 or 1)
                end
                state.ready_button:SetIsEnabled(v.can_ready==true)
                state.ready_text:SetText(FText(v.ready and'Снять готовность'or'Готов'))
                state.launch_button:SetVisibility(v.host and 0 or (options.simple and 1 or 2))
                state.launch_button:SetIsEnabled(v.can_start==true)
            end
            end
        end
        return true
    end
    if options.log then options.log('main_menu_entry_attached',entry:GetFullName())end
    return state
end
function M.boot(output,capture)
    assert(os.getenv('AC8_COOP_MENU')=='25201480','Menu profile is absent')
    local entry=assert(os.getenv('AC8_COOP_MENU_ENTRY'));local root=assert(entry:match('^(.*)[/\\][^/\\]+$'))
    local services=assert(loadfile(root..'/coop_menu_services.lua'))()(output,capture)
    local controller=assert(loadfile(root..'/coop_menu_session.lua'))().new(services)
    local is_lobby=os.getenv('AC8_COOP_LOBBY')=='25201480'
    if is_lobby then
        local route=assert(loadfile(root..'/coop_lobby_route.lua'))().game(services,output)
        local api=assert(loadfile(root..'/coop_lobby_services.lua'))()(services,controller,root,output,route)
        controller=assert(loadfile(root..'/coop_lobby_session.lua'))().new(api,controller)
    end
    local runtime={controller=controller,ui=nil,seen_main=false,pending=0,update_at=0}
    _G.AC8CoopMenuRuntime=runtime
    local options={
        log=services.log,status=function()return controller.detail end,
        configure=function(role,peer)controller.configure(role,peer)end,
        lobby=is_lobby,continuous=services.continuous,simple=services.continuous,
        ready=function()controller.ready();if not is_lobby and runtime.ui then runtime.ui.close()end end,
        start=function()controller.select(7,23);controller.start()end,
        view=function()return {phase=controller.phase,host=controller.role=='host',ready=controller.ready_local,can_ready=controller.phase=='room'and controller.connected,can_start=is_lobby and controller.can_start()}end,
        reset=function()if controller.reset then controller.reset()end end,
        stop=function()controller.stop();controller.report()end,report=controller.report,
        error=function(e)services.log('ui_error',e)end,
        restore=function(role,edit)
            local path=os.getenv('AC8_COOP_MENU_SETTINGS');local f=path and io.open(path,'r')
            if not f then return end
            local data=f:read(257);f:close();if not data or #data>256 then return end
            local peer=data:match('\npeer\t([1-9]%d+)\r?\n');local selected=data:match('\nrole\t(%a+)\r?\n')
            if peer and #peer==17 and (selected=='host'or selected=='guest')then
                role:SetSelectedIndex(selected=='host'and 0 or 1);edit:SetText(FText(peer))
            end
        end,
    }
    local function drive()
        local ok,err=pcall(function()
            if runtime.seen_main and not runtime.ui then
                runtime.ui=M.attach(options)
                if runtime.ui then
                    runtime.last_error=nil
                    if controller.phase=='idle'then controller.detail='Введите SteamID64 друга, затем создайте лобби или присоединитесь.'end
                end
            end
            if runtime.ui and not runtime.ui.refresh()then runtime.ui=nil;runtime.seen_main=false end
            if os.time()~=runtime.update_at then runtime.update_at=os.time();controller.update()end
        end)
        if not ok then
            if runtime.last_error~=tostring(err)then services.log('menu_driver_error',err);runtime.last_error=tostring(err)end
            controller.detail='Ошибка меню. Сохраните отладочный отчёт.'
            if controller.consent then pcall(controller.stop,'Ошибка интерфейса; опыт остановлен.');services.report()end
        end
        ExecuteInGameThreadWithDelay(runtime.ui and 16 or 500,_G.AC8CoopMenuDrive)
    end
    _G.AC8CoopMenuDrive=drive
    -- Do not inventory every UserWidget during startup/GC. Construction only signals;
    -- any object access and attachment happen later on the game thread, in the exact class.
    _G.AC8CoopMenuMainCreated=function()runtime.seen_main=true end
    NotifyOnNewObject('/Script/Live.LiveMenuMainTopWidget',_G.AC8CoopMenuMainCreated)
    ExecuteInGameThreadWithDelay(1000,drive)
    services.log('boot','stock_main_menu_f14d_mission6')
end
return M
