assert(os.getenv('AC8_MISSION_SYNC')=='25201480','Synchronized local profile required')
local source=assert(os.getenv('AC8_LOCAL_SCRIPTS'));local output=assert(os.getenv('AC8_COOP_RECON_OUTPUT'));local dll=assert(os.getenv('AC8_LOCAL_DLL'))
local native={start=assert(package.loadlib(dll,'luaopen_ac8_local_start')),clock=assert(package.loadlib(dll,'luaopen_ac8_sync26_clock'))}
local function log(event,detail)local f=io.open(output..'/local-menu.log','a');if f then f:write(os.date('%Y-%m-%d %H:%M:%S'),'\t',event,'\t',tostring(detail or''):gsub('[\r\n]',' '),'\n');f:close()end end
local controller=assert(loadfile(source..'/mission_sync_services.lua'))().new(output,assert(os.getenv('AC8_LOCAL_TOKEN')),native,log)
local menu=assert(loadfile(source..'/coop_main_menu.lua'))();local catalog=assert(loadfile(source..'/coop_menu_catalog.lua'))()
local options={compact=true,source=source,catalog=catalog,is_host=true,local_session=true,status=controller.status,view=controller.view,select=controller.select,ready=controller.ready,open_hangar=controller.open_hangar,log=log,error=function(e)log('ui_error',e)end}
_G.AC8LocalController=controller;_G.AC8LocalOptions=options
local ui;local adapter;local job=''
controller.start();log('r26_loaded','one host game; virtual guest; synchronized barriers')
local function tick()
 local ok,err=pcall(function()
  controller.poll()
  if os.getenv('AC8_LOCAL_ADAPTER_DEV')=='25201480'then
   local f=io.open(output..'/sync-job.txt','r');local id=f and f:read(60);if f then f:close()end
   if id and id:match('^[%w_-]+$')and id~=job then
    job=id;local file=assert(io.open(source..'/sync_job.lua','rb'));local text=file:read('*a');file:close()
    local saved=assert(io.open(output..'/sync-job-'..id..'.lua','wb'));saved:write(text);saved:close()
    assert(load(text,'@sync_job.lua','t'))()(output,id,controller)
   end
  end
  if not adapter then
   local f=io.open(source..'/mission_sync_adapter.lua','r');if f then f:close();adapter=assert(loadfile(source..'/mission_sync_adapter.lua'))().new(controller,output,source,log);_G.AC8MissionSyncAdapter=adapter end
  end
  if adapter then adapter.update()end
  if not ui or not ui.refresh()then ui=menu.attach(options)end
 end)
 if not ok then log('sync_tick_error',err)end
 ExecuteInGameThreadWithDelay(16,tick)
end
ExecuteInGameThreadWithDelay(1000,tick)
