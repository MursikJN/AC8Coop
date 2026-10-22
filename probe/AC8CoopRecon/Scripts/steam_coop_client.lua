-- Client consumes the host scene, never clicks its own campaign menus.
-- The world provider must load and verify an isolated replica world. A lobby
-- handshake, an ordinary locally running mission, or a preview is not proof.
local M={}
function M.new(c,output,source,native,log,provider)
 local codec=assert(loadfile(source..'/scene_codec.lua'))()
 local view=assert(loadfile(source..'/guest_pilot_view.lua'))()
 local pilot=assert(loadfile(source..'/steam_coop_pilot.lua'))().new(c,output,source,native,log)
 local s={ready=false,isolated_world_verified=false,stream=view.stream(),loaded_epochs={}}
 local function count(t)local n=0;for _ in pairs(t or{})do n=n+1 end;return n end
 function s.diagnostics()
  local e=s.engine;local core=e and e.core;local cam=s.camera;local pose=e and e.guest_pose
  return {provider_phase=provider and provider.phase,provider_checks=provider and provider.checks,provider_reason=provider and provider.reason,
   pilot_active=pilot.active,pilot_loaded=pilot.loaded,pilot_reason=pilot.reason,
   scene_sequence=core and core.sequence,scene_source_ms=core and core.current and core.current.source_ms,scene_received_host_ms=core and core.received,
   scene_age_ms=core and core.received and c.now-core.received,events_applied=core and core.events_applied,event_cursor=core and core.event_cursor,needs_baseline=core and core.needs_baseline,
   entities=e and count(e.entities),models=e and count(e.nodes),pending_models=e and count(e.pending),assets_ready=e and e.assets_ready,
   camera_active=cam and cam.active,camera_updates=cam and cam.updates,camera_reason=cam and cam.reason,
   guest_x=pose and pose.position[1],guest_y=pose and pose.position[2],guest_z=pose and pose.position[3],last_frame_reason=s.last_frame_reason}
 end
 local function read(name,limit)
  local f=io.open(output..'/'..name,'rb');if not f then return end;local data=f:read(limit+1);f:close();if #data>limit then return end;return data
 end
 function s.stop(reason)
  if s.camera then s.camera.stop(reason);s.camera=nil end;pilot.stop(reason)
  if s.context then s.context.local_owner_verified=false;s.context.local_owner_actor=nil end
  if s.engine then s.engine.stop(reason);s.engine=nil end
  if provider and provider.stop then provider.stop(reason)end;s.ready=false;s.isolated_world_verified=false;s.reason=reason
 end
 function s.drain()pilot.update(s);return not pilot.cleanup_pending end
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
   local frame_reason=frame.session.mission~=6 and'wrong_mission'or frame.revision~=tonumber(c.snapshot.revision)and'wrong_revision'or frame.session.stage~=phase and'wrong_stage'or frame.world~=context.world:GetFullName()and'wrong_world'or not frame.visual_complete and'incomplete_visuals'or frame.sequence<=s.engine.core.sequence and'old_sequence'or'candidate'
   if frame.sequence~=s.last_observed_sequence then
    s.last_observed_sequence=frame.sequence
    s.last_frame_reason=frame_reason
    if s.last_frame_reason~='candidate'and c.trace then c.trace('scene_frame_ignored',{sequence=frame.sequence,reason=s.last_frame_reason})end
   end
   if frame_reason=='candidate'then
    local ok,why=s.engine.accept(data,c.now,s.engine.core.sequence==0);assert(ok,why)
    s.last_frame_reason='accepted'
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
  local local_running=native.pilot_prepare and pilot.active and context.local_owner_verified and s.engine.ready
  s.ready=local_running or(s.engine.ready and s.engine.core.active and initial_pose()~=nil);s.isolated_world_verified=true
  if not s.ready then return end
  if not s.camera then
   s.camera=assert(loadfile(source..'/guest_pilot_camera.lua'))().new(view)
   s.camera.attach(context.pc,function()
    if context.local_owner_verified and not context.local_owner_spectating and s.engine.owner_pose then return s.engine.owner_pose end
    local received=s.stream.sample(c.now)
    if received then return received.poses[(received.flags&2)~=0 and 1 or 2]end
    return initial_pose()
   end,{replica_context=context,verify_replica=function()return provider.verify(context)end})
  end
  if phase==5 and not c.pending and not s.loaded_epochs[c.snapshot.epoch]then c.loaded();s.loaded_epochs[c.snapshot.epoch]=true end
  if phase==6 and not pilot.active then pilot.try_start(s)end
  if native.pilot_prepare and pilot.reason then error(pilot.reason)end
  pilot.update(s)
  if context.local_owner_verified then
   local local_state=read('guest-owner-local.ac8p',392)
   if local_state then s.engine.set_owner_pose(view.owner(local_state))end
  end
  local state=read('guest-pilot-state.ac8p',392)
  if state then
   local frame=view.parse(state)
   if frame.generation==tonumber(c.snapshot.generation)and frame.revision==tonumber(c.snapshot.revision)then
    s.stream.accept(frame,c.now)
    if native.pilot_prepare and(frame.flags&2)~=0 then context.local_owner_spectating=true;s.engine.owner_pose=nil end
   end
  end
 end
 function s.update()
  if s.error then s.drain();return end
  local ok,err=xpcall(update,debug.traceback)
  if not ok then s.error=tostring(err);s.stop(s.error);c.error='Клиентская сцена: '..s.error;log('coop_client_error',s.error)end
 end
 return s
end
return M
