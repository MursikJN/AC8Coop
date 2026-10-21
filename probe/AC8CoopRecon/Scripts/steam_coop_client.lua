-- Client consumes the host scene, never clicks its own campaign menus.
-- The world provider must load and verify an isolated replica world. A lobby
-- handshake, an ordinary locally running mission, or a preview is not proof.
local M={}
function M.new(c,output,source,native,log,provider)
 local codec=assert(loadfile(source..'/scene_codec.lua'))()
 local view=assert(loadfile(source..'/guest_pilot_view.lua'))()
 local pilot=assert(loadfile(source..'/steam_coop_pilot.lua'))().new(c,output,source,native,log)
 local s={ready=false,isolated_world_verified=false,stream=view.stream(),loaded_epochs={}}
 local function read(name,limit)
  local f=io.open(output..'/'..name,'rb');if not f then return end;local data=f:read(limit+1);f:close();if #data>limit then return end;return data
 end
 function s.stop(reason)
  pilot.stop(reason);if s.camera then s.camera.stop(reason);s.camera=nil end
  if s.engine then s.engine.stop(reason);s.engine=nil end
  if provider and provider.stop then provider.stop(reason)end;s.ready=false;s.isolated_world_verified=false;s.reason=reason
 end
 local function update()
  local v=c.view();local phase=v.phase
  if c.cinema then c.cinema.update();if c.cinema.error then s.reason=c.cinema.error;return end end
  if not v.connected or phase==8 then s.stop('room_unavailable');return end
  if phase==0 or phase==4 then return end
  if not provider then s.reason='isolated_client_world_loader_required';c.info='Ожидание загрузчика клиентской сцены.';return end
  -- Providers return true only after their actual stage/asset operation ends.
  if phase==1 or phase==3 then
   local stage=provider.prepare_stage(phase,v.scene,c.snapshot)
   if stage and stage.ready and stage.session_token==c.token and not c.pending and not s.loaded_epochs[c.snapshot.epoch]then
    c.loaded();s.loaded_epochs[c.snapshot.epoch]=true
   end
   return
  elseif phase==2 and(c.cinema or tonumber(c.snapshot.scene_return)~=6)then provider.cutscene(c.snapshot);return end
  if phase~=5 and phase~=6 and not(phase==2 and tonumber(c.snapshot.scene_return)==6)then return end
  local context=provider.prepare_flight(c.snapshot)
  if not context or context.session_token~=c.token or context.generation~=tonumber(c.snapshot.generation)or context.revision~=tonumber(c.snapshot.revision)or not provider.verify(context)then s.reason='waiting_verified_replica_world';return end
  assert(context.isolated_world_verified==true and not context.preview and not context.live_preview,'Independent client scene required')
  if not s.engine then s.context=context;s.engine=assert(loadfile(source..'/scene_engine.lua'))().new(context,source);s.stream=view.stream()end
  assert(s.context==context,'Replica world context changed without teardown')
  local data=read('scene-client.ac8w',codec.MAX_BYTES)
  if data then
   local frame=codec.decode(data)
   if frame.session.mission==6 and frame.revision==tonumber(c.snapshot.revision)and frame.session.stage==phase and frame.world==context.world:GetFullName()and frame.visual_complete and frame.sequence>s.engine.core.sequence then
    local ok,why=s.engine.accept(data,c.now,s.engine.core.sequence==0);assert(ok,why)
   end
  end
  s.engine.pump(2)
  if s.engine.core.current and s.engine.assets_ready then
   local rendered=s.engine.render(c.now)
   if rendered and next(s.engine.nodes)and not s.engine.ready then s.engine.activate(c.now)end
  end
  local function initial_pose()
   if s.engine.guest_pose then return s.engine.guest_pose end
   -- Baxter appears after the host's IGC. Until then show the replicated host
   -- aircraft; do not wait for Baxter before acknowledging terrain loading.
   for _,e in pairs(s.engine.entities)do if e.role==0 and e.alive then return e end end
  end
  s.ready=s.engine.ready and s.engine.core.active and initial_pose()~=nil;s.isolated_world_verified=true
  if not s.ready then return end
  if not s.camera then
   s.camera=assert(loadfile(source..'/guest_pilot_camera.lua'))().new(view)
   s.camera.attach(context.pc,function()
    local received=s.stream.sample(c.now)
    if received then return received.poses[(received.flags&2)~=0 and 1 or 2]end
    return initial_pose()
   end,{replica_context=context,verify_replica=function()return provider.verify(context)end})
  end
  if phase==5 and not c.pending and not s.loaded_epochs[c.snapshot.epoch]then c.loaded();s.loaded_epochs[c.snapshot.epoch]=true end
  if phase==6 and not pilot.active then pilot.try_start(s)end
  pilot.update(s)
  local state=read('guest-pilot-state.ac8p',368)
  if state then
   local frame=view.parse(state)
   if frame.generation==tonumber(c.snapshot.generation)and frame.revision==tonumber(c.snapshot.revision)then s.stream.accept(frame,c.now)end
  end
 end
 function s.update()
  if s.error then return end
  local ok,err=xpcall(update,debug.traceback)
  if not ok then s.error=tostring(err);s.stop(s.error);c.error='Клиентская сцена: '..s.error;log('coop_client_error',s.error)end
 end
 return s
end
return M
