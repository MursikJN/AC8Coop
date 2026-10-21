-- Recovery controls on the already used stock cinematic canvas. Hidden during
-- ordinary flight; the host can request a shared restart from a paused flight.
local M={}
local function valid(o)return o and o:IsValid()end
function M.new(c,log)
 local r={};local library=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local function release_input()
  if r.input and valid(r.pc)then library:SetInputMode_GameAndUIEx(r.pc,r.widget,0,false,true);r.pc.bShowMouseCursor=r.cursor end;r.input=false
 end
 local function construct(kind,tree,name)return assert(StaticConstructObject(assert(StaticFindObject('/Script/UMG.'..kind)),tree,FName(name)))end
 local function attach()
  local cls=LoadAsset('/Game/Blueprints/UI/Cinematics/WBP_Cinema_SkipButton_000.WBP_Cinema_SkipButton_000_C')
  local pc=require('UEHelpers').GetPlayerController();assert(valid(cls)and valid(pc),'Нет контекста восстановления.')
  r.widget=library:Create(pc,cls,pc);local root=r.widget.RootPanel;assert(valid(root)and root:IsA('/Script/UMG.CanvasPanel'))
  for i=0,root:GetChildrenCount()-1 do root:GetChildAt(i):SetVisibility(1)end
  r.page=construct('VerticalBox',r.widget.WidgetTree,'AC8_Recovery_Page')
  local slot=root:AddChildToCanvas(r.page);r.slot=slot;slot:SetPosition({X=90,Y=180});slot:SetSize({X=1600,Y=700})
  r.info=construct('TextBlock',r.widget.WidgetTree,'AC8_Recovery_Status');r.info.Font.Size=30;r.info:SetAutoWrapText(true);r.page:AddChildToVerticalBox(r.info)
  r.controls={}
  for _,spec in ipairs({{'Cancel','ОТМЕНИТЬ ПОДГОТОВКУ',c.cancel},{'Restart','ПЕРЕЗАПУСТИТЬ СЕССИЮ',c.restart},{'Quit','ВЫЙТИ ИЗ ИГРЫ',function()c.lifecycle.quit()end}})do
   local b=construct('Button',r.widget.WidgetTree,'AC8_Recovery_'..spec[1]);local t=construct('TextBlock',r.widget.WidgetTree,'AC8_Recovery_Text_'..spec[1]);t.Font.Size=32;t:SetText(FText(spec[2]));b:AddChild(t)
   local s=r.page:AddChildToVerticalBox(b);s:SetPadding({Left=0,Top=15,Right=0,Bottom=15});r.controls[#r.controls+1]={name=spec[1],button=b,action=spec[3]}
  end
  root:SetVisibility(4);r.page:SetVisibility(4);r.widget:AddToViewport(2000);r.serial=_G.AC8MainMenuClickSerial or 0;r.pc=pc
 end
 function r.update()
  local v=c.view();local phase=v.phase
  local pc=require('UEHelpers').GetPlayerController()
  local paused=valid(pc)and StaticFindObject('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc:GetWorld())
  local cinematic_wait=phase==2 and((tonumber(c.snapshot.cinema_state)or 0)<2 or(c.cinema and c.cinema.waiting))
  local show=v.session_policy and(phase==8 or phase==9 or phase==10 or v.local_failure or phase==1 or phase==3 or phase==5 or cinematic_wait or(c.role=='host'and phase==6 and paused))
  if not show then if valid(r.widget)then r.widget:SetVisibility(1)end;release_input();return end
  if valid(r.widget)and(not valid(r.pc)or r.pc:GetAddress()~=pc:GetAddress())then release_input();r.widget:RemoveFromParent();r.widget=nil end
  if not valid(r.widget)then attach()end
  local manual_hangar=phase==3 and c.role=='host'
  if not r.input and not manual_hangar then
   r.cursor=r.pc.bShowMouseCursor
   if phase==6 then library:SetInputMode_GameAndUIEx(r.pc,r.controls[1].button,0,false,true)else library:SetInputMode_UIOnlyEx(r.pc,r.controls[1].button,0,true)end
   r.pc.bShowMouseCursor=true;r.input=true
  end
  r.slot:SetAnchors(manual_hangar and{Minimum={X=1,Y=1},Maximum={X=1,Y=1}}or{Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
  r.slot:SetAlignment(manual_hangar and{X=1,Y=1}or{X=0,Y=0})
  r.slot:SetPosition(manual_hangar and{X=-40,Y=-40}or{X=90,Y=180});r.slot:SetSize(manual_hangar and{X=500,Y=200}or{X=1600,Y=700})
  r.info:SetVisibility(manual_hangar and 1 or 0)
  r.widget:SetVisibility(4);r.info:SetText(FText(c.status()..(r.error and'\n'..r.error or'')..'\nПрогресс кампании сохраняется только хосту.'))
  local serial=_G.AC8MainMenuClickSerial or 0;local click=serial~=r.serial;r.serial=serial
  for _,ctl in ipairs(r.controls)do
   local enabled=ctl.name=='Cancel'and v.can_cancel or ctl.name=='Restart'and v.can_restart or ctl.name=='Quit'and v.can_quit and not manual_hangar
   ctl.button:SetIsEnabled(enabled==true);ctl.button:SetVisibility(enabled and 0 or 1)
   local down=ctl.button:IsPressed()
   if enabled and((click and ctl.button:IsHovered())or(down and not ctl.down))then local ok,err=pcall(ctl.action);r.error=not ok and tostring(err)or nil;log('recovery_action',ctl.name..':'..tostring(ok));ctl.down=down;break end
   ctl.down=down
  end
 end
 function r.stop()release_input();if valid(r.widget)then r.widget:RemoveFromParent()end end
 return r
end
return M
