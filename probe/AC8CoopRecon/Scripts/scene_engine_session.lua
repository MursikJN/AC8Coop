-- One-process visual acceptance harness; full client world loading is separate.
local M={}
local function valid(o)return o and o:IsValid()end
function M.start(output,source,pc)
 assert(os.getenv('AC8_SCENE_VIEWER')=='25201480'and os.getenv('AC8_LOCAL_ROLE')=='host','Local scene preview profile required')
 local world=pc:GetWorld();local pawn=pc.Pawn;local source_host=assert(_G.AC8SceneHost)
 local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics');local paused=gameplay:IsGamePaused(world)
 local clock=assert(loadfile(source..'/scene_clock.lua'))();local codec=assert(loadfile(source..'/scene_codec.lua'))()
 local view=assert(loadfile(source..'/guest_pilot_view.lua'))()
 local s={active=true,phase='loading_models',last_sequence=0,last_generation=0,last_report=0,started=clock.milliseconds(world)}
 local camera=assert(loadfile(source..'/guest_pilot_camera.lua'))().new(view);s.camera=camera
 local function original(id)
  for _,r in pairs(source_host.registry)do if r.id==id then return r.object end end
 end
 local visibility=not paused and assert(loadfile(source..'/scene_visibility.lua'))().new(pc,world)or nil
 local engine=assert(loadfile(source..'/scene_engine.lua'))().new({preview=paused,live_preview=not paused,visibility=visibility,world=world,pc=pc,original_for_id=original},source);s.engine=engine;_G.AC8SceneEngine=engine
 local function save()
  local nodes,pending,entities=0,0,0;for _ in pairs(engine.nodes)do nodes=nodes+1 end;for _ in pairs(engine.pending)do pending=pending+1 end;for _ in pairs(engine.entities)do entities=entities+1 end
  local f=io.open(output..'/scene-engine-status.tsv','w');if f then
   f:write('active\t',s.active and 1 or 0,'\nphase\t',s.phase,'\nready\t',engine.ready and 1 or 0,'\nsequence\t',engine.core.sequence,'\nentities\t',entities,'\nmodels\t',nodes,'\npending_models\t',pending,'\ncreated_models\t',engine.created,'\ndestroy_requested\t',engine.destroy_requested,'\ncamera_updates\t',camera.updates,'\nreason\t',(s.reason or''):gsub('[\r\n\t]',' '),'\ninput_enabled\t0\nseparate_guest_world_verified\t0\nfull_mission_replication\t0\n');f:close()
  end
 end
 function s.stop(reason)
  s.active=false;s.phase='stopped';s.reason=reason
  if s.loop then CancelDelayedAction(s.loop);s.loop=nil end
  if s.quality then s.quality.restore();s.quality=nil end
  camera.stop(reason);engine.stop(reason);save()
 end
 local function tick()
  local now=clock.milliseconds(world)
  if s.live_until and now>=s.live_until then s.stop('live_replica_preview_complete');return end
  assert(valid(pawn)and valid(pc.Pawn)and pc.Pawn:GetAddress()==pawn:GetAddress(),'Host pawn changed during replica preview')
  local f=io.open(output..'/scene-client-preview.ac8w','rb')
  if f then
   local head=f:read(512)or'';local seq,generation=head:match('\nframe\t(%d+)\t(%d+)\t');seq=tonumber(seq);generation=tonumber(generation)
   if seq and(generation~=s.last_generation or seq>s.last_sequence)then
    f:seek('set',0);local data=f:read(codec.MAX_BYTES+1);f:close();f=nil
    local ok,reason=engine.accept(data,now,engine.core.sequence==0);assert(ok,'Replica frame refused: '..tostring(reason))
    s.last_sequence=seq;s.last_generation=generation
   end
   if f then f:close()end
  end
  assert(engine.core.current,'No received visual baseline')
  engine.pump(1)
  if s.phase=='rendering_models'or s.phase=='waiting_network'then
   local rendered=engine.render(now)
   if rendered then
    s.phase='rendering_models';s.network_gap=nil
    if engine.assets_ready and not engine.ready then engine.activate(now)end
   else
    -- A missed visual snapshot freezes the last replica pose. It never
    -- resumes AI or destroys the scene while waiting for a fresh baseline.
    s.phase='waiting_network';s.network_gap=s.network_gap or now
    assert(now-s.network_gap<10000,'Replica transport stopped responding')
   end
  else
   assert(now-s.started<20000,'Replica model loading timed out')
   if engine.assets_ready and now-engine.core.received<=500 then
    local rendered,reason=engine.render(now);assert(rendered,reason);engine.activate(now)
   elseif engine.assets_ready then s.phase='waiting_fresh_baseline'end
  end
  if engine.ready then
   if not s.camera_attached then
    assert(engine.guest_pose,'Guest mesh pose unavailable')
    camera.attach(pc,function()return s.active and engine.guest_pose or nil end,paused and{preview=true}or{observer=true,duration=15});s.camera_attached=true
    if not paused then s.live_until=now+12000 end
    local hud=pc:GetHUD()
    if valid(hud)and type(hud.bShowHUD)=='boolean'then engine.panels[#engine.panels+1]={object=hud,attribute='bShowHUD',value=hud.bShowHUD};hud.bShowHUD=false end
    if valid(hud)then for _,key in ipairs({'HudWidget','HudMenuWidget','GlowWidgetPtr','NonGlowFrontWidgetPtr','NonGlowBackWidgetPtr'})do
     local widget=hud[key];if valid(widget)then engine.panels[#engine.panels+1]={object=widget,visibility=widget.Visibility};widget:SetVisibility(1)end
    end end
    for _,widget in ipairs(FindAllOf('WBP_MenuCommon_InputGuide_000_C')or{})do if valid(widget)and widget:IsInViewport()then
     engine.panels[#engine.panels+1]={object=widget,visibility=widget.Visibility};widget:SetVisibility(1)
    end end
    for _,widget in ipairs(FindAllOf('LiveMenuPauseBootWidget')or{})do
     if valid(widget)and valid(widget:GetWorld())and widget:GetWorld():GetAddress()==world:GetAddress()then
      engine.panels[#engine.panels+1]={object=widget,visibility=widget.Visibility};widget:SetVisibility(1)
     end
    end
    s.phase='rendering_models'
   end
   assert(camera.active,'Replica camera stopped: '..tostring(camera.reason))
  end
  if now-s.last_report>=500 then s.last_report=now;save()end
 end
 s.loop=LoopInGameThreadAfterFrames(1,function()
  if not s.active then return end
  local ok,err=xpcall(tick,debug.traceback);if not ok then s.stop(err)end
 end)
 save();return s
end
return M
