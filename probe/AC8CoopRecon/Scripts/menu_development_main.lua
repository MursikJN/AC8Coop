-- Dedicated UI development profile. No automatic native flight/Steam calls.
local output=assert(os.getenv('AC8_COOP_RECON_OUTPUT'))
assert(os.getenv('AC8_COOP_RECON')=='1')
local task=assert(os.getenv('AC8_COOP_RECON_EXTENSION'))
local root=task:match('^(.*)[/\\][^/\\]+$')
local last_job,active='',false
local function loop()
    local ok,err=pcall(function()
        if not active then return end
        local job=io.open(root..'/menu-job.txt','r');local id=job and job:read(64)or'inspect';if job then job:close()end
        id=id:gsub('[^%w_-]',''):sub(1,60)
        if id==last_job then return end
        last_job=id
        local source=assert(io.open(task,'r'));local text=source:read('*a');source:close()
        local stamp=os.date('%Y%m%d-%H%M%S')..'-'..id
        local archive=assert(io.open(output..'/menu-task-'..stamp..'.lua','w'));archive:write(text);archive:close()
        local fn=assert(load(text,'@'..task,'t'))();assert(type(fn)=='function');fn(output,stamp)
    end)
    if not ok then
        local f=io.open(output..'/menu-development-errors.log','a');if f then f:write(os.date(),' ',tostring(err),'\n');f:close()end
        print('[AC8Menu] '..tostring(err)..'\n')
    end
    ExecuteInGameThreadWithDelay(1000,loop)
end
_G.AC8MenuDevelopmentLoop=loop -- keep callbacks rooted across UE4SS callback collection
RegisterKeyBind(Key.F8,function()
    ExecuteInGameThread(function()active=true;last_job='';loop()end)
end)
-- Development only: enter the main menu before the first explicit snapshot.
-- Later jobs run on the existing game-thread loop without another key press.
print('[AC8Menu] development profile: F8 once in the stock main menu; no startup object scan.\n')
