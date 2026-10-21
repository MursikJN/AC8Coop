-- A separate display-only instance of the loaded stock skip widget. Original
-- children are hidden; no stock skip input/manager is attached to this instance.
local M={}
local function valid(o)return o and o:IsValid()end
function M.new(controller,log)
 local r={}
 function r.template(template)
  if valid(r.widget)or not valid(template)then return end
  local player=require('UEHelpers').GetPlayerController()
  local library=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
  local widget=library:Create(player,template:GetClass(),player)
  assert(valid(widget)and valid(widget.RootPanel)and widget.RootPanel:IsA('/Script/UMG.CanvasPanel'),'Нет штатного контейнера статуса.')
  local root=widget.RootPanel;assert(root:GetChildrenCount()<=32)
  for i=0,root:GetChildrenCount()-1 do root:GetChildAt(i):SetVisibility(1)end
  local label=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),widget.WidgetTree,FName('AC8_Coop_SessionStatus_R26'))
  assert(valid(label));label.Font.Size=30;label:SetVisibility(3)
  local slot=root:AddChildToCanvas(label);slot:SetPosition({X=80,Y=85});slot:SetSize({X=1700,Y=100})
  root:SetVisibility(3);widget:SetVisibility(3);widget:AddToViewport(1000)
  r.widget=widget;r.label=label;log('sync_status_ui','stock display template / no input')
 end
 function r.update()
  if not valid(r.widget)then r.widget=nil;return end
  local phase=controller.view().phase
  r.widget:SetVisibility((phase==1 or phase==2 or phase==5)and 3 or 1)
  if valid(r.label)then r.label:SetText(FText(controller.status()..(phase==2 and' · Удерживайте Esc для голоса'or'')))end
 end
 return r
end
return M
