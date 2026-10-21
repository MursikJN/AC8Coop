-- Development lobby only. No ClientTravel, title bypass, synthetic menus or flight actor.
assert(os.getenv('AC8_LOCAL_SESSION')=='25201480','Local session profile required')
local output=assert(os.getenv('AC8_COOP_RECON_OUTPUT'))
local source=assert(os.getenv('AC8_LOCAL_SCRIPTS'))
local host=os.getenv('AC8_LOCAL_ROLE')=='host'
local token=assert(os.getenv('AC8_LOCAL_TOKEN'))
local start=assert(package.loadlib(assert(os.getenv('AC8_LOCAL_DLL')),'luaopen_ac8_local_start'))
local menu=assert(loadfile(source..'/coop_main_menu.lua'))()
local catalog=assert(loadfile(source..'/coop_menu_catalog.lua'))()
local controller=assert(loadfile(source..'/shared_session_local_services.lua'))().new(output,host,token,start,catalog)
local ui=nil
local dev_job=''
local function log(event,detail)
 local f=io.open(output..'/local-menu.log','a');if f then f:write(os.date('%Y-%m-%d %H:%M:%S'),'\t',event,'\t',tostring(detail or ''),'\n');f:close()end
end
controller.start();log('transport_requested',host and 'host' or 'guest')
local options={local_session=true,is_host=host,log=log,error=function(e)log('ui_error',e)end,
 status=controller.status,view=controller.view,ready=controller.ready,select=controller.select}
options.compact=true;options.source=source;options.catalog=catalog
options.hangar_adapter=os.getenv('AC8_LOCAL_HANGAR')=='25201480'
options.open_hangar=controller.open_hangar
_G.AC8LocalController=controller;_G.AC8LocalOptions=options
if (os.getenv('AC8_SCENE_VIEWER')=='25201480'or os.getenv('AC8_SCENE_STEAM')=='25201480')and host then
 _G.AC8SceneHost=assert(loadfile(source..'/scene_host.lua'))().new(output,source,controller)
 _G.AC8ScenePreview=assert(loadfile(source..'/scene_preview.lua'))().new(output,source)
end
if os.getenv('AC8_SCENE_STEAM')=='25201480'then _G.AC8SceneSteam=assert(loadfile(source..'/scene_steam.lua'))().start()end
if options.hangar_adapter then
 local available=io.open(source..'/local_hangar_adapter.lua','r')
 if available then available:close();_G.AC8LocalHangarAdapter=assert(loadfile(source..'/local_hangar_adapter.lua'))().new(controller,output,source,log)end
end
local function tick()
 local ok,problem=pcall(function()
  controller.poll()
  if _G.AC8SceneHost then _G.AC8SceneHost.update()end
  if _G.AC8ScenePreview then _G.AC8ScenePreview.update()end
  if _G.AC8SceneSteam then _G.AC8SceneSteam.update()end
  if _G.AC8LocalHangarAdapter then _G.AC8LocalHangarAdapter.update()end
  if os.getenv('AC8_LOCAL_ADAPTER_DEV')=='25201480'then
   local f=io.open(output..'/adapter-job.txt','r');local id=f and f:read(60);if f then f:close()end
   if id and id:match('^[%w_-]+$')and id~=dev_job then
    dev_job=id;local code=assert(io.open(source..'/local_adapter_task.lua','r'));local text=code:read('*a');code:close()
    local saved=assert(io.open(output..'/adapter-job-'..id..'.lua','w'));saved:write(text);saved:close()
    assert(load(text,'@local_adapter_task.lua','t'))()(output,id,controller)
   end
  end
  if not ui or not ui.refresh()then ui=menu.attach(options)end
 end)
 if not ok then log('tick_error',problem)end
 ExecuteInGameThreadWithDelay(100,_G.AC8LocalSessionTick)
end
_G.AC8LocalSessionTick=tick
ExecuteInGameThreadWithDelay(1000,tick)
