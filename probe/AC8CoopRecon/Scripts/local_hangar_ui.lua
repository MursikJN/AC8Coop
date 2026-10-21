local M={}
local function valid(o)return o and o:IsValid()end
local function make(path,outer,name)return assert(StaticConstructObject(assert(StaticFindObject(path)),outer,FName(name)))end
function M.attach(widget,controller,status,start)
 local list
 local class=widget:GetClass()
 for _=1,8 do
  if not valid(class)then break end
  class:ForEachProperty(function(p)
   local name=p:GetFName():ToString()
   if p:GetClass():GetFName():ToString()=='ObjectProperty'and name:find('Command',1,true)then
    pcall(function()local o=widget[name];if valid(o)and o:IsA('/Script/Live.LiveMenuCommandListWidget')then list=o end end)
   end
  end);class=class:GetSuperStruct()
 end
 assert(valid(list),'Не найден штатный список команд ангара.')
 local canvas=list:GetParent()
 for _=1,6 do if not valid(canvas)or canvas:IsA('/Script/UMG.CanvasPanel')then break end;canvas=canvas:GetParent()end
 assert(valid(canvas)and canvas:IsA('/Script/UMG.CanvasPanel'),'Не найден штатный CanvasPanel ангара.')
 local page=make('/Script/UMG.VerticalBox',widget.WidgetTree,'AC8_Hangar_Coop')
 local slot=canvas:AddChildToCanvas(page);slot:SetPosition({X=250,Y=300});slot:SetSize({X=1300,Y=700})
 local function label(name,caption,size)
  local o=make('/Script/UMG.TextBlock',widget.WidgetTree,name);o.Font.Size=size;o:SetText(FText(caption));o:SetAutoWrapText(true);page:AddChildToVerticalBox(o);return o
 end
 label('AC8_Hangar_Title','СОВМЕСТНЫЙ ВЫЛЕТ',48)
 local info=label('AC8_Hangar_Info','',35)
 local controls={}
 local function button(name,caption,action)
  local b=make('/Script/UMG.Button',widget.WidgetTree,name)
  local t=make('/Script/UMG.TextBlock',widget.WidgetTree,name..'_Text');t.Font.Size=42;t:SetText(FText(caption));b:AddChild(t)
  local s=page:AddChildToVerticalBox(b);s:SetPadding({Left=0,Top=10,Right=0,Bottom=10})
  controls[#controls+1]={button=b,text=t,action=action};return b,t
 end
 local ready,ready_text=button('AC8_Hangar_Ready','Готов в ангаре',controller.ready)
 local sortie=button('AC8_Hangar_Start','Начать миссию',start)
 local visibility=list.Visibility;list:SetVisibility(1)
 local player=require('UEHelpers').GetPlayerController();local library=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 assert(valid(player)and valid(library),'Нет контроллера ангара.')
 library:SetInputMode_UIOnlyEx(player,ready,0,true);player.bShowMouseCursor=true
 local serial=_G.AC8MainMenuClickSerial or 0;local error_text=nil
 local ui={widget=widget}
 function ui.refresh()
  if not valid(widget)or not valid(page)then return false end
  local current=_G.AC8MainMenuClickSerial or 0;local click=current~=serial;serial=current
  local v=controller.view();ready:SetIsEnabled(v.can_ready==true);sortie:SetIsEnabled(v.can_start_flight==true)
  ready_text:SetText(FText(v.ready and'Снять готовность'or'Готов в ангаре'))
  info:SetText(FText(error_text or status()))
  for _,c in ipairs(controls)do
   local down=c.button:IsPressed()
   if c.button.bIsEnabled and((click and c.button:IsHovered())or(down and not c.down and not c.button:IsHovered()))then
    local ok,err=pcall(c.action);error_text=not ok and tostring(err)or nil;c.down=down;break
   end;c.down=down
  end
  return true
 end
 function ui.close()
  if valid(page)then page:SetVisibility(1)end;if valid(list)then list:SetVisibility(visibility)end
  if valid(player)then library:SetInputMode_GameAndUIEx(player,widget,0,false,true);player.bShowMouseCursor=false end
 end
 return ui
end
return M
