-- One-game camera preview from the *received* replica stream. Does not possess,
-- move or tick the host/AI aircraft. This is not a second game client.
local M={}
function M.new(output,source)
 local codec=assert(loadfile(source..'/scene_codec.lua'))()
 local clock=assert(loadfile(source..'/scene_clock.lua'))()
 local view=assert(loadfile(source..'/guest_pilot_view.lua'))()
 local camera=assert(loadfile(source..'/guest_pilot_camera.lua'))().new(view)
 local s={camera=camera,last_request=0,last_sequence=0,reason='idle'}
 local function fields(path)
  local f=io.open(path,'rb');if not f then return{}end;local body=f:read(4097);f:close();assert(#body<=4096,'Preview command budget');local r={}
  for k,v in body:gmatch('([^\t\r\n]+)\t([^\r\n]*)')do assert(not r[k]);r[k]=v end;return r
 end
 local function save()
  local f=io.open(output..'/scene-camera-status.tsv','w');if f then f:write('active\t',camera.active and 1 or 0,'\nreason\t',(s.reason or camera.reason or''):gsub('[\r\n\t]',' '),'\nupdates\t',camera.updates,'\nsource\treceived_client_snapshot\n');f:close()end
 end
 function s.update()
  local ok,err=xpcall(function()
   local f=io.open(output..'/scene-client-preview.ac8w','rb')
   if f then local data=f:read(codec.MAX_BYTES+1);f:close();local frame=codec.decode(data)
    if not s.last_generation or frame.generation>s.last_generation or(frame.generation==s.last_generation and frame.sequence>s.last_sequence)then
     local pc;for _,o in ipairs(FindAllOf('LivePlayerController')or{})do if o:IsValid()and o:GetWorld():IsValid()then assert(not pc);pc=o end end
     assert(pc and pc:GetWorld():GetFullName()==frame.world,'Preview world unavailable');s.world=pc:GetWorld()
     s.frame=frame;s.last_sequence=frame.sequence;s.last_generation=frame.generation;s.received=clock.milliseconds(s.world)
    end
   end
   local r=fields(output..'/scene-camera-command.tsv');local request=tonumber(r.request)
   if request and request~=s.last_request then
    s.last_request=request;assert(math.abs(os.time()-(tonumber(r.created_unix)or 0))<=3,'Stale camera command')
    assert(r.mode=='host'or r.mode=='guest'or r.mode=='replica','Unknown camera command')
    if s.engine then s.engine.stop('preview_mode_changed');s.engine=nil end
    if r.mode=='host'then camera.stop('host_requested');s.reason='host_camera_restored'
    else
     local age=s.world and clock.milliseconds(s.world)-s.received
     assert(s.frame and s.frame.complete and age and age>=0 and age<1000,'No fresh received scene')
     local pc;for _,o in ipairs(FindAllOf('LivePlayerController')or{})do if o:IsValid()and o.Pawn and o.Pawn:IsValid()and o.Pawn:IsA('/Script/Live.LivePlayerPlane')then assert(not pc);pc=o end end
     assert(pc and pc:GetWorld():GetFullName()==s.frame.world,'Host/replica scene mismatch')
     local function pose()
      local age=clock.milliseconds(s.world)-s.received
      if not s.frame or age<0 or age>1000 then return nil end
      for _,e in ipairs(s.frame.entities)do if e.role==1 and e.alive then return e end end
     end
     if r.mode=='replica'then
      camera.stop('start_visual_replica');s.engine=assert(loadfile(source..'/scene_engine_session.lua'))().start(output,source,pc);s.reason='client_mesh_replica_preview'
     else
      local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics');local paused=gameplay:IsGamePaused(pc.Pawn)
      camera.attach(pc,pose,paused and{preview=true}or{observer=true,duration=15})
      s.reason=paused and'guest_camera_from_received_scene'or'live_observer_from_received_scene'
     end
    end
   end
   if not camera.active and camera.reason then s.reason=camera.reason end
  end,debug.traceback)
  if not ok then camera.stop(err);s.reason=err end;save()
 end
 function s.stop()if s.engine then s.engine.stop('scene_preview_stopped');s.engine=nil end;camera.stop('scene_preview_stopped');save()end
 return s
end
return M
