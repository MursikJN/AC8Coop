-- Compact page inside MainTop's own canvas and animations. No viewport overlay.
local M={}
function M.build(state,options,ui)
 local tree=state.main.WidgetTree;local grid=state.grid;local parent=grid:GetParent()
 assert(parent:IsA('/Script/UMG.CanvasPanel'),'Main content parent changed')
 local make=function(kind,name)return ui.construct('/Script/UMG.'..kind,tree,name)end
 local page=make('VerticalBox','AC8_Lobby_Page');state.page=page
 local slot=parent:AddChildToCanvas(page);local anchors=grid.Slot:GetAnchors();local alignment=grid.Slot:GetAlignment();local p=grid.Slot:GetPosition()
 slot:SetAnchors({Minimum={X=anchors.Minimum.X,Y=anchors.Minimum.Y},Maximum={X=anchors.Maximum.X,Y=anchors.Maximum.Y}})
 slot:SetAlignment({X=alignment.X,Y=alignment.Y});slot:SetPosition({X=p.X+75,Y=p.Y+300});slot:SetSize({X=1350,Y=1000})
 local catalog=assert(options.catalog);local model=assert(loadfile(options.source..'/coop_lobby_frontend.lua'))().new(options,catalog)
 local panels={};local buttons={};local info={};local function label(box,name,caption,size)
  local t=ui.text(tree,name,caption,size or 28);local s=box:AddChildToVerticalBox(t);s:SetPadding({Left=0,Top=6,Right=0,Bottom=6});return t
 end
 local function panel(name)local b=make('VerticalBox',name);page:AddChildToVerticalBox(b);panels[name]=b;return b end
 local function button(box,name,caption,action)
  local b,t=ui.button(tree,name,caption,37);b:SetBackgroundColor({R=1,G=1,B=1,A=0})
  local s=box:AddChildToVerticalBox(b);s:SetPadding({Left=0,Top=6,Right=0,Bottom=6});s:SetHorizontalAlignment(0)
  local c={widget=b,label=t,action=action,was_pressed=false,visible=true};state.controls[#state.controls+1]=c;buttons[name]=c;return c
 end
 label(page,'AC8_Lobby_Context','КАМПАНИЯ  /  2 ИГРОКА',23)
 local tabs=panel('AC8_Lobby_Tabs')
 local create_tab=button(tabs,'AC8_Lobby_CreateTab','СОЗДАТЬ ЛОББИ',function()model.mode('create')end)
 local join_tab=button(tabs,'AC8_Lobby_JoinTab','ПРИСОЕДИНИТЬСЯ',function()model.mode('join')end)
 local settings=panel('AC8_Lobby_Settings')
 label(settings,'AC8_Lobby_SettingsLabel','ПАРАМЕТРЫ МИССИИ',22)
 local mission=label(settings,'AC8_Lobby_Mission','ЗАДАНИЕ 6',37)
 local expanded=false
 local difficulty=button(settings,'AC8_Lobby_Difficulty','',function()expanded=not expanded end)
 local choices=make('VerticalBox','AC8_Lobby_DifficultyChoices');settings:AddChildToVerticalBox(choices)
 local choice_buttons={}
 for _,e in ipairs(catalog.difficulties)do
  choice_buttons[#choice_buttons+1]={entry=e,control=button(choices,'AC8_Lobby_Difficulty_'..e.value,e.caption,function()model.select(6,e.value);expanded=false end)}
 end
 local join=panel('AC8_Lobby_JoinFields')
 label(join,'AC8_Lobby_PeerLabel','STEAMID64 ХОСТА',22)
 local peer=make('EditableTextBox','AC8_Lobby_Peer');peer.Font.Size=37;peer:SetForegroundColor({R=.045,G=.055,B=.065,A=1});peer:SetHintText(FText('17 цифр'));join:AddChildToVerticalBox(peer)
 local enter=button(page,'AC8_Lobby_Enter','СОЗДАТЬ',function()if not model.enter(peer:GetText():ToString())then error(model.error,0)end end)
 local room=panel('AC8_Lobby_Room')
 info.summary=label(room,'AC8_Lobby_Summary','',31)
 label(room,'AC8_Lobby_Players','УЧАСТНИКИ',22)
 info.host=label(room,'AC8_Lobby_HostRow','',34)
 info.guest=label(room,'AC8_Lobby_GuestRow','',34)
 info.aircraft=label(room,'AC8_Lobby_Aircraft','',24)
 local loadout=options.loadout and button(room,'AC8_Lobby_Loadout','ВЫБРАТЬ F-14D',function()options.loadout(23)end)
 info.host_id=options.create and label(room,'AC8_Lobby_HostID','',23)
 local invite=options.invite and button(room,'AC8_Lobby_Invite','ПРИГЛАСИТЬ ДРУГА',function()if not model.invite()then error(model.error,0)end end)
 local primary=button(room,'AC8_Lobby_Primary','ГОТОВ',function()if not model.primary()then error(model.error,0)end end)
 local unready=button(room,'AC8_Lobby_Unready','СНЯТЬ ГОТОВНОСТЬ',function()if not model.unready()then error(model.error,0)end end)
 local leave=options.leave and button(room,'AC8_Lobby_Leave','ВЫЙТИ ИЗ ЛОББИ',function()if not model.leave()then error(model.error,0)end end)
 -- Unready is independent of the primary action, which becomes Continue only
 -- after both acknowledgements. A click must never launch and unready together.
 state.status=label(page,'AC8_Lobby_Status','',25);state.status:SetAutoWrapText(true)
 button(page,'AC8_Lobby_Back','В ГЛАВНОЕ МЕНЮ',state.close)
 label(page,'AC8_Lobby_Logs','Отладочные журналы сохраняются автоматически.',20)
 state.peer=options.is_host and difficulty.widget or join_tab.widget
 local function shown(object,show)object:SetVisibility(show and 0 or 1)end
 local function control(c,show,enabled,caption)
  c.visible=show;shown(c.widget,show);c.widget:SetIsEnabled(show and enabled)
  if caption then c.caption=caption end
  local hover=show and enabled and c.widget:IsHovered();c.label:SetText(FText((hover and'›  'or'')..(c.caption or'')))
  c.widget:SetBackgroundColor({R=1,G=1,B=1,A=hover and .92 or 0})
  c.label:SetColorAndOpacity({SpecifiedColor=hover and{R=.045,G=.055,B=.065,A=1}or(enabled and{R=.91,G=.94,B=.94,A=1}or{R=.46,G=.51,B=.53,A=1}),ColorUseRule=0})
 end
 create_tab.caption='СОЗДАТЬ ЛОББИ';join_tab.caption='ПРИСОЕДИНИТЬСЯ'
 local compact={model=model,peer=peer}
 local header,original_header;local help=state.main.HelpText;local original_help
 local function find_header(o,depth)
  if header or not o or not o:IsValid()or depth>10 then return end
  if o:IsA('/Script/UMG.TextBlock')then header=o;original_header=o:GetText():ToString()
  elseif o:IsA('/Script/UMG.UserWidget')then find_header(o.WidgetTree.RootWidget,depth+1)
  elseif o:IsA('/Script/UMG.PanelWidget')then for i=0,math.min(o:GetChildrenCount(),24)-1 do find_header(o:GetChildAt(i),depth+1)end end
 end
 find_header(state.main.Header,0)
 function compact.open()
  if options.log then options.log('frontend_open',model.view().screen)end
  if header and header:IsValid()then header:SetText(FText('СОВМЕСТНАЯ ИГРА'))end
  if help and help:IsValid()then original_help=help.Visibility;help:SetVisibility(1)end
 end
 function compact.close()
  if options.log then options.log('frontend_back_to_main',model.view().screen)end
  if header and header:IsValid()and header:GetText():ToString()=='СОВМЕСТНАЯ ИГРА'then header:SetText(FText(original_header))end
  if help and help:IsValid()and original_help~=nil and help.Visibility==1 then help:SetVisibility(original_help)end
 end
 function compact.refresh(error_text)
  local v=model.view()
  shown(tabs,not v.room);shown(settings,v.screen=='create'or(v.room and v.host));shown(join,v.screen=='join');shown(room,v.room)
  control(create_tab,not v.room and v.fixed_role~='guest',true,(v.screen=='create'and'●  'or'')..'СОЗДАТЬ ЛОББИ')
  control(join_tab,not v.room and v.fixed_role~='host',true,(v.screen=='join'and'●  'or'')..'ПРИСОЕДИНИТЬСЯ')
  mission:SetText(FText(v.mission_caption));control(difficulty,v.screen=='create'or(v.room and v.host),v.can_edit,'СЛОЖНОСТЬ:  '..v.difficulty_caption..(expanded and'  ‹'or'  ›'))
  shown(choices,expanded);for _,choice in ipairs(choice_buttons)do control(choice.control,expanded and(v.screen=='create'or(v.room and v.host)),v.can_edit,(v.difficulty==choice.entry.value and'✓  'or'    ')..choice.entry.caption)end
  control(enter,not v.room,v.can_enter,v.screen=='create'and'СОЗДАТЬ'or'ПОДКЛЮЧИТЬСЯ')
  control(primary,v.room,v.can_primary,v.primary);control(unready,v.room and v.can_unready,true,'СНЯТЬ ГОТОВНОСТЬ')
  if loadout then control(loadout,v.room and not v.host,v.can_loadout,'ВЫБРАТЬ F-14D')end
  if invite then control(invite,v.room and v.host,v.can_invite,'ПРИГЛАСИТЬ ДРУГА')end
  if leave then control(leave,v.room,v.can_leave,'ВЫЙТИ ИЗ ЛОББИ')end
  if info.host_id then info.host_id:SetText(FText('STEAMID64 ХОСТА: '..(v.host_id or'…')))end
  info.summary:SetText(FText(v.mission_caption..'  /  '..v.difficulty_caption))
  shown(info.summary,not v.host)
  info.host:SetText(FText((v.host_ready and'✓  'or'—  ')..v.host_name..'  ·  ХОСТ'))
  info.guest:SetText(FText((v.connected and(v.guest_ready and'✓  'or'—  ')or'…  ')..(v.connected and v.guest_name or'Ожидание участника')..'  ·  ГОСТЬ'))
  info.aircraft:SetText(FText('Самолёт гостя: '..v.guest_aircraft..(v.lobby_only and''or'  ·  Свой самолёт выберете в ангаре.')))
  state.status:SetText(FText(error_text or v.detail))
  for name,c in pairs(buttons)do if name=='AC8_Lobby_Back'then c.caption='В ГЛАВНОЕ МЕНЮ';control(c,true,true)end end
  compact.view=v
 end
 compact.refresh();return compact
end
return M
