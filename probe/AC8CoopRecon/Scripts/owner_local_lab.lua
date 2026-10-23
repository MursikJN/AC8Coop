-- One-game experiment, explicitly separate from a real Steam session.
-- The protocol helper supplies barriers only. Production native Backend owns
-- creation, stock physics, identity/readback checks and retirement.
local M={}
function M.new(source,output,dll,api)
 api=api or{static=StaticFindObject,find=FindAllOf}
 local function module(name)return assert(loadfile(source..'/'..name..'.lua'))()end
 local function write(name,text)local f=assert(io.open(output..'/'..name,'wb'));assert(f:write(text));f:close()end
 local function read(name)local f=io.open(output..'/'..name,'rb');if not f then return end;local data=f:read(16385);f:close();assert(#data<=16384);return data end
 local function status(name)local text=read(name);local r={};for k,v in (text or''):gmatch('([%w_]+)\t([^\r\n]*)')do r[k]=v end;return r end
 local native=api.native or{};if not api.native then for _,name in ipairs({'start','tick','stop','loaded','capture_input','prepare','preflight','clock','track_camera','retain_template'})do native[name]=assert(package.loadlib(dll,'luaopen_ac8_pilot_'..name))end end
 local last_clock,last_clock_wall;local wall_now=api.wall_now or os.time
 local now=api.now or function()
  native.clock();local at=assert(tonumber(status('owner-lab-clock.tsv').monotonic_ms),'Native monotonic clock unavailable')
  local wall=wall_now()
  if at~=last_clock then last_clock=at;last_clock_wall=wall
  else assert(wall-last_clock_wall<3,'Native monotonic clock stopped updating')end
  return at
 end
 local c={role='guest',token='local-native-lab',now=now(),snapshot={mission='6',difficulty='1',guest_aircraft='23',guest_weapon1='0',guest_weapon2='0',guest_mod_count='0',generation='1',revision='1'}}
 local d=api.diagnostic or module('session_diagnostics').new(output,{session_id=os.getenv('AC8_SESSION_ID'),role='guest',package='r31-local-native-lab'});d.context(c)
 local function log(name,detail)d.log(name,tostring(detail or''))end
 local provider=api.provider or module('steam_coop_client_world').new(c,output,source,log)
 local view=module('guest_pilot_view');local preparation=api.preparation or module('guest_owner_preparation')
 local s={phase='waiting_title',active=true,pose_updates=0,sequence=0,paused=false};local camera,context,pose
 local function clean(v)return tostring(v or''):gsub('[\r\n\t]',' ')end
 local function save()
  local st=status('guest-pilot-status.tsv')
  local rows={'mode\tone_game_native_backend_no_steam','profile\tlocal-stage1','phase\t'..s.phase,'error\t'..clean(s.error),'cleanup_error\t'..clean(s.cleanup_error),'cleanup_complete\t'..(s.complete and'1'or'0'),'paused\t'..(s.paused and'1'or'0'),'pose_updates\t'..s.pose_updates,'pose_sequence\t'..s.sequence,'camera_updates\t'..(camera and camera.updates or s.camera_updates or 0),'owner_preflight_ready\t'..(st.owner_preflight_ready or'0'),'dependency_reason\t'..clean(st.owner_detail),'native_steps\t'..(st.owner_native_steps or'0'),'input_samples\t'..(st.owner_input_samples or'0'),'flight_acceptance\tNOT_ACCEPTED_AUTOMATICALLY','runtime_seconds\t'..(s.running_at and math.max(0,c.now-s.running_at)/1000 or 0),'cleanup_reason\t'..clean(st.owner_cleanup_reason),'camera_retired\t'..(st.owner_camera_retired or'0')}
  if pose then rows[#rows+1]=string.format('x\t%.17g\ny\t%.17g\nz\t%.17g\nspeed\t%.9g',pose.position[1],pose.position[2],pose.position[3],pose.speed)end
  write('owner-lab-status.tsv',table.concat(rows,'\n')..'\n')
 end
 function s.stop(reason)
  if s.closing then return end;s.closing=true;s.phase='cleanup';s.cleanup_at=c.now;log('owner_lab_stop',reason)
  local function attempt(fn)local ok,why=pcall(fn);if not ok then s.cleanup_error=clean(why);log('owner_lab_cleanup_error',why)end end
  -- Revoke input/physics even when camera restoration fails. Continue draining
  -- native identities; no failed cleanup can be reported as complete.
  if s.started or s.native_cleanup_required then attempt(native.stop)end
  if camera then s.camera_updates=camera.updates;attempt(function()camera.stop(reason)end);if not camera.active then camera=nil end end
  if context then context.local_owner_actor=nil;context.local_owner_verified=false end
  attempt(function()provider.stop(reason)end)
  -- A key callback may arrive long after the last scene tick. Start the GC
  -- grace period from a fresh clock AFTER teardown requests, not cached c.now.
  attempt(function()local at=now();assert(at>=c.now,'Cleanup clock regressed');c.now=at;s.cleanup_at=at end);save()
 end
 function s.pause()if not s.closing then s.paused=not s.paused;log('owner_lab_pause',s.paused);save()end end
 local function step()
  local at=now();assert(at>=c.now,'Monotonic clock regressed');c.now=at
  if s.closing then
   if s.started or s.native_cleanup_required then native.tick();local st=status('guest-pilot-status.tsv');s.complete=st.owner_cleanup_complete=='1'and not s.cleanup_error and camera==nil
    if not s.complete and not s.cleanup_error and camera==nil and st.owner_gc_safe=='1'and c.now-s.cleanup_at>=250 and c.now-(s.last_gc or 0)>=1000 then api.static('/Script/Engine.Default__KismetSystemLibrary'):CollectGarbage();s.last_gc=c.now end
   else s.complete=not s.cleanup_error and camera==nil end
   if s.complete then s.active=false;s.phase=s.error and'failed_cleaned'or'stopped'
   elseif c.now-s.cleanup_at>30000 then s.phase='cleanup_unconfirmed';s.active=false;log('owner_lab_cleanup_unconfirmed','New process required; no object ID reuse')end
   save();return
  end
  if not context then
   if not provider.requested then
    local main=false;for _,o in ipairs(api.find('LiveMenuMainTopWidget')or{})do if o:IsValid()and o:IsVisible()then main=true end end
    if not main then return end
   end
   s.loading_at=s.loading_at or c.now;assert(c.now-s.loading_at<120000,'Local world preparation timed out')
   context=provider.prepare_flight(c.snapshot);if not context then s.phase='preparing_isolated_world';save();return end
   assert(context.isolated_world_verified and provider.verify(context),'Lab world isolation failed')
   local at=context.pawn:K2_GetActorLocation()
   -- Deliberate lab stimulus: own Pawn XY, +1500 m altitude, level +X heading,
   -- 250 m/s. This is not a captured host mission or a claimed safe spawn site.
   pose={role=1,aircraft=23,position={at.X,at.Y,at.Z+150000},rotation={0,0,0,1},speed=250}
   camera=(api.camera or module('guest_pilot_camera').new(view));camera.attach(context.pc,function()return pose end,{replica_context=context,verify_replica=function()return provider.verify(context)end})
   -- Register exact camera identity before asset loading or start can fail.
   s.native_cleanup_required=true
   write('guest-owner-camera.tsv','created_unix\t'..wall_now()..'\ncamera\t'..string.format('0x%x',camera.camera:GetAddress())..'\n')
   native.track_camera()
   if status('guest-pilot-status.tsv').owner_camera_tracked~='1'then s.cleanup_error='Camera retirement receipt unavailable';error(s.cleanup_error)end
   local peer=status('owner-lab-peer.tsv');assert(tonumber(peer.port)and tonumber(peer.token),'Local helper is unavailable')
   local rows={'role\tguest','transport\tloopback','generation\t1','revision\t1','port\t'..peer.port,'token\t'..peer.token}
   preparation.request(c,{context=context,camera=camera},rows)
   -- Same GT callback as LoadAsset, before yielding to any GC/timer or peer wait.
   write('guest-owner-template.tsv',table.concat(rows,'\n')..'\ncreated_unix\t'..wall_now()..'\n')
   native.retain_template()
   assert(status('guest-pilot-status.tsv').owner_template_retained=='1','F-14D template retention refused')
   write('owner-lab-host-seed.tsv',string.format('x\t%.17g\ny\t%.17g\nz\t%.17g\nqx\t0\nqy\t0\nqz\t0\nqw\t1\nspeed\t250\n',table.unpack(pose.position)))
   c.now=now() -- asset loading may have blocked this callback for many seconds
   rows[#rows+1]='created_unix\t'..wall_now();write('guest-pilot-request.tsv',table.concat(rows,'\n')..'\n')
   s.started=true;native.start();assert(status('guest-pilot-status.tsv').active=='1','Local native pilot start refused');s.started_at=c.now;s.phase='waiting_initial_state';save()
  end
  assert(provider.verify(context),'Lab isolation lost')
  assert(camera and camera.active,'Local camera stopped: '..clean(camera and camera.reason))
  if camera.updates~=s.camera_updates then s.camera_updates=camera.updates;s.camera_at=c.now end
  assert(not s.camera_at or c.now-s.camera_at<2000,'Local camera update stalled')
  write('guest-pilot-clock.tsv','created_unix\t'..os.time()..'\npaused\t'..(s.paused and'1'or'0')..'\n')
  if s.loaded then native.capture_input()end
  native.tick()
  local st=status('guest-pilot-status.tsv');assert(st.active=='1','Native pilot stopped: '..tostring(st.engine_detail)..' / '..tostring(st.state))
  if not s.prepared then
   local bytes=read('guest-pilot-state.ac8p')
   assert(c.now-s.started_at<45000,'Owner preparation timed out: '..clean(st.owner_detail))
   if bytes then
    if not s.last_preflight or c.now-s.last_preflight>=1000 then native.preflight();s.last_preflight=c.now;st=status('guest-pilot-status.tsv')end
    if st.owner_preflight_ready~='1'then s.phase='waiting_dependencies';save();return end
    local frame=view.parse(bytes);assert(frame.generation==1 and frame.revision==1,'Foreign initial state');write('guest-owner-seed.tsv',preparation.seed(frame,view));native.prepare();st=status('guest-pilot-status.tsv');assert(st.owner_ready=='1','Stock model refused: '..tostring(st.owner_detail));s.prepared=true;s.prepared_at=c.now
    local pointer=assert(tonumber(st.owner_pointer));local owner
    for _,o in ipairs(api.find('BP_PlayerPlane_PP0023_f14d_C')or{})do if o:IsValid()and o:GetAddress()==pointer then assert(not owner);owner=o end end
    assert(owner and owner:GetWorld():GetAddress()==context.world:GetAddress(),'Local owner actor missing')
    context.local_owner_actor=owner;context.local_owner_verified=true;owner:SetActorEnableCollision(false)
    owner:SetActorHiddenInGame(false);s.phase='local_model_ready';log('owner_lab_native_ready',st.owner_detail)
   end
  end
  if s.prepared then
   if not s.loaded then native.loaded();s.loaded=status('guest-pilot-status.tsv').state=='guest_world_loaded_sent';if s.loaded then native.capture_input()end end
   local bytes=read('guest-owner-local.ac8p')
   if bytes then local frame=view.owner(bytes);assert(frame.generation==1 and frame.revision==1 and frame.sequence>=s.sequence,'Foreign/replayed local pose')
    if frame.sequence>s.sequence then pose=frame.pose;s.sequence=frame.sequence;s.pose_updates=s.pose_updates+1;s.pose_at=c.now;s.running_at=s.running_at or c.now end
   end
   if s.paused then s.pose_at=c.now;s.phase='local_model_paused'
   else assert(c.now-(s.pose_at or s.prepared_at)<5000,'Local model produced no fresh pose');s.phase=s.pose_updates>0 and'local_model_running'or'waiting_loaded_ack_and_pose'end
  end
  save();d.observe(c,{client=s})
 end
 function s.step()local ok,why=xpcall(step,debug.traceback);if not ok then s.error=s.error or tostring(why);c.error=s.error;log('owner_lab_error',s.error);if s.closing then s.cleanup_error=tostring(why);s.phase='cleanup_unconfirmed';s.active=false;save()else s.stop(s.error)end;d.observe(c,{client=s})end end
 save();return s
end
function M.run(source,output,dll)
 local handle={};local s
 RegisterKeyBind(Key.F9,function()ExecuteInGameThread(function()if s then s.stop('user_f9')else handle.cancelled=true end end)end)
 RegisterKeyBind(Key.F10,function()ExecuteInGameThread(function()if s then s.pause()end end)end)
 local function tick()
  if handle.cancelled then return end
  if not s then
   -- M.new calls the native clock and engine libraries. Its FIRST call must
   -- already be on GT: native setup pins the thread for every later call.
   local ok,result=xpcall(function()return M.new(source,output,dll)end,debug.traceback)
   if not ok then
    handle.error=tostring(result);local f=io.open(output..'/owner-lab-status.tsv','wb')
    if f then f:write('phase\tinitialization_failed\nerror\t',handle.error:gsub('[\r\n\t]',' '),'\ncleanup_complete\t0\n');f:close()end
    return
   end
   s=result;handle.state=s
  end
  s.step();if s.active then ExecuteInGameThreadWithDelay(16,tick)end
 end
 ExecuteInGameThreadWithDelay(1000,tick);return handle
end
return M
