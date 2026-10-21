-- Game-thread adapters for the stock-menu controller. No UI/render hooks or OS windows.
return function(output,capture)
    assert(os.getenv('AC8_COOP_MENU')=='25201480','menu launcher missing')
    local dll=assert(os.getenv('AC8_COOP_PLANE_FLIGHT_DLL'))
    local configure=assert(package.loadlib(dll,'luaopen_ac8_coop_menu_configure'))
    local api={now=os.time,continuous=os.getenv("AC8_COOP_CONTINUOUS")=="25201480"};local report_id=0
    local function read(name,optional)
        local f=io.open(output..'/'..name,'r');if not f and optional then return{}end;assert(f,'Missing '..name)
        local text=f:read(16385);f:close();assert(text and #text<=16384,'Oversized '..name)
        local fields={};for line in text:gmatch('[^\r\n]+')do local k,v=line:match('^([^\t]+)\t(.*)$');if k then fields[k]=v end end
        return fields
    end
    local function write(path,text)
        local f=assert(io.open(path..'.tmp','w'));assert(f:write(text));assert(f:close())
        local old=io.open(path,'r');if old then old:close();assert(os.remove(path))end
        assert(os.rename(path..'.tmp',path))
    end
    function api.log(action,detail)
        local f=assert(io.open(output..'/coop-menu-events.tsv','a'))
        f:write(os.date('!%Y-%m-%dT%H:%M:%SZ'),'\t',action,'\t',tostring(detail):gsub('[\r\n\t]',' '):sub(1,2048),'\n');f:close()
    end
    function api.configure(role,peer)
        local text='format\tac8-coop-menu-v1\nrole\t'..role..'\npeer\t'..peer..'\nmission\t7\nplane\t23\n'
        write(output..'/coop-menu-settings.tsv',text);configure()
        local n=read('plane-flight-status.tsv')
        assert(n.status=='menu_configured'and n.module_revision==(api.continuous and 'r10'or'r8') and (not api.continuous or n.lifetime_ms=='0'),'Native menu configuration rejected: '..tostring(n.reason))
        local settings=os.getenv('AC8_COOP_MENU_SETTINGS')
        if settings then write(settings,text)end
    end
    function api.flight_supported()
        local count=0
        for _,pc in ipairs(FindAllOf('LivePlayerController')or{})do
            if pc:IsValid()then
                local pawn=pc.Pawn
                if pawn and pawn:IsValid()and pawn:IsA('/Script/Live.LivePlayerPlane')then
                    count=count+1
                    local world=pc:GetWorld()
                    if not world:IsValid()or not world:GetFullName():find('Mission007',1,true)then return false,'Откройте задание 6 обычным способом.'end
                    if not pawn:GetClass():GetFullName():find('/PP0023_f14d/',1,true)then return false,'Выберите F-14D в ангаре.'end
                    if not pawn.bIsActivated or pawn.bIsIGCActor then return false,'Ожидание управляемого полёта после дозаправки.'end
                end
            end
        end
        return count==1,count==1 and 'Готов к проверке.'or'Откройте задание 6, F-14D; после дозаправки нажмите «Готов».'
    end
    function api.preflight()
        local stamp=capture()
        local path=assert(os.getenv('AC8_COOP_RECON_EXTENSION'))
        local f=assert(io.open(path,'r'));local text=f:read('*a');f:close()
        write(output..'/auto-flight-probe-'..stamp..'.lua',text)
        assert(load(text,'@'..path,'t'))()(output,stamp)
        local state=assert(_G.AC8PlaneFlightLifecycle,'flight lifecycle missing')
        assert(state.ready and not state.attempted,'native preflight refused')
        return state
    end
    function api.status()return read('plane-flight-status.tsv'),read('coop-status.tsv',true)end
    function api.arm(stamp)
        assert(stamp:match('^[%w_-]+$')and #stamp<=64,'invalid stamp')
        local request=read('plane-flight-request.tsv');local age=os.time()-assert(tonumber(request.created_unix))
        assert(request.stamp==stamp and age>=0 and age<100,'preflight expired')
        write(output..'/plane-flight-armed.txt',stamp)
        write(output..'/r8-automatic-arm.tsv','stamp\t'..stamp..'\ncreated_unix\t'..os.time()..'\nconsent\tstock_menu_ready\n')
    end
    function api.report()
        report_id=report_id+1;write(output..'/coop-report-request.txt',os.time()..'-'..report_id)
    end
    return api
end
