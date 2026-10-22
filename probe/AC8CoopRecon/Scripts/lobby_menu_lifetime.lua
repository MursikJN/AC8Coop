-- MainTop belongs to the menu world. Never poll its retained wrapper after
-- campaign handoff, even if Lua still holds the old table/userdata.
local M={}
local function valid(o)return o and o:IsValid()end
function M.new(menu,options,log)
 local r={retired=false}
 local function forget()
  if _G.AC8MainMenuEntry==r.ui then _G.AC8MainMenuEntry=nil end
  r.ui=nil
 end
 function r.poll()
  if r.retired then return false end
  if r.ui and not valid(r.ui.main)then forget()end
  if not r.ui then r.ui=menu.attach(options)end
  return r.ui~=nil and valid(r.ui.main)and r.ui.main:IsVisible()==true
 end
 function r.handoff(controller)
  if r.retired or (tonumber(controller.snapshot.phase)or 0)==0 then return end
  -- Latch before calling close: never retry a partial close against a world
  -- which may have started tearing down. No RemoveFromParent on stale objects.
  r.retired=true
  local ui=r.ui
  forget()
  if ui and valid(ui.main)then ui.close()end
  log('main_menu_retired','campaign handoff; no further MainTop calls')
 end
 function r.refresh()
  if r.retired or not r.ui then return end
  if not valid(r.ui.main)or not r.ui.refresh()then forget()end
 end
 return r
end
return M
