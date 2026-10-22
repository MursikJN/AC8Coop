-- One-game experiment, explicitly separate from a real Steam session.
-- The protocol helper supplies barriers only. Production native Backend owns
-- creation, stock physics, identity/readback checks and retirement.
local M={}
function M.new(source,output,dll,api)
 api=api or{static=StaticFindObject,find=FindAllOf,now=function()return os.time()*1000 end}
 local function module(name)return assert(loadfile(source..'/'..name..'.lua'))()end
 local function write(name,text)local f=assert(io.open(output..'/'..name,'wb'));assert(f:write(text));f:close()end
 local function read(name)local f=io.open(output..'/'..name,'rb');if not f then return end;local data=f:read(16385);f:close();assert(#data<=16384);return data end
 local function status(name)local text=read(name);local r={};for k,v in (text or''):gmatch('([%w_]+)\t([^\r\n]*)')do r[k]=v end;return r end
 local native=api.native or{};if not api.native then for _,name in ipairs({'start','tick','stop','loaded','capture_input','prepare'})do native[name]=assert(package.loadlib(dll,'luaopen_ac8_pilot_'..name))end end
 local c={role='guest',token='local-native-lab',now=api.now(),snapshot={mission='6',difficulty='1',guest_aircraft='23',guest_weapon1='0',guest_weapon2='0',guest_mod_count='0',generation='1',revision='1'}}
 local d=api.diagnostic or module('session_diagnostics').new(output,{session_id=os.getenv('AC8_SESSION_ID'),role='guest',package='r31-local-native-lab'});d.context(c)
 local function log(name,detail)d.log(name,tostring(detail or''))end
 local provider=api.provider or module('steam_coop_client_world').new(c,output,source,log)
 local view=module('guest_pilot_view');local preparation=api.preparation or module('guest_owner_preparation')
 local s={phase='waiting_title',active=true};local camera,context,pose
 local function save()
  write('owner-lab-status.tsv','mode\tone_game_native_backend_no_steam\nphase\t'..s.phase..'\nerror\t'..tostring(s.error or'')..'\ncleanup_complete\t'..(s.complete and'1'or'0')..'\n')
 end
 function s.stop(reason)
  if s.closing then return end;s.closing=true;s.phase='cleanup';log('owner_lab_stop',reason)
  if camera then camera.stop(reason);camera=nil end
  if s.started then native.stop()end
  if context then context.local_owner_actor=nil;context.local_owner_verified=false end
  provider.stop(reason);save()
 end
 local function step()
  c.now=api.now()
  if s.closing then
   if s.started then native.tick();local st=status('guest-pilot-status.tsv');s.complete=st.owner_cleanup_complete=='1'
    if not s.complete and c.now-(s.last_gc or 0)>=1000 then api.static('/Script/Engine.Default__KismetSystemLibrary'):CollectGarbage();s.last_gc=c.now end
   else s.complete=true end
   if s.complete then s.active=false;s.phase='stopped'end;save();return
  end
  if not context then
   if not provider.requested then
    local main=false;for _,o in ipairs(api.find('LiveMenuMainTopWidget')or{})do if o:IsValid()and o:IsVisible()then main=true end end
    if not main then return end
   end
   context=provider.prepare_flight(c.snapshot);if not context then s.phase='preparing_isolated_world';save();return end
   assert(context.isolated_world_verified and provider.verify(context),'Lab world isolation failed')
   local at=context.pawn:K2_GetActorLocation()
   -- Deliberate lab stimulus: own Pawn XY, +1500 m altitude, level +X heading,
   -- 250 m/s. This is not a captured host mission or a claimed safe spawn site.
   pose={role=1,aircraft=23,position={at.X,at.Y,at.Z+150000},rotation={0,0,0,1},speed=250}
   camera=(api.camera or module('guest_pilot_camera').new(view));camera.attach(context.pc,function()return pose end,{replica_context=context,verify_replica=function()return provider.verify(context)end})
   local peer=status('owner-lab-peer.tsv');assert(tonumber(peer.port)and tonumber(peer.token),'Local helper is unavailable')
   local rows={'created_unix\t'..os.time(),'role\tguest','transport\tloopback','generation\t1','revision\t1','port\t'..peer.port,'token\t'..peer.token}
   preparation.request(c,{context=context,camera=camera},rows);write('guest-pilot-request.tsv',table.concat(rows,'\n')..'\n')
   write('owner-lab-host-seed.tsv',string.format('x\t%.17g\ny\t%.17g\nz\t%.17g\nqx\t0\nqy\t0\nqz\t0\nqw\t1\nspeed\t250\n',table.unpack(pose.position)))
   s.started=true;native.start();assert(status('guest-pilot-status.tsv').active=='1','Local native pilot start refused');s.phase='waiting_initial_state';save()
  end
  assert(provider.verify(context),'Lab isolation lost')
  write('guest-pilot-clock.tsv','created_unix\t'..os.time()..'\npaused\t0\n');native.tick()
  local st=status('guest-pilot-status.tsv');assert(st.active=='1','Native pilot stopped: '..tostring(st.engine_detail)..' / '..tostring(st.state))
  if not s.prepared then
   local bytes=read('guest-pilot-state.ac8p')
   if bytes then local frame=view.parse(bytes);write('guest-owner-seed.tsv',preparation.seed(frame,view));native.prepare();st=status('guest-pilot-status.tsv');assert(st.owner_ready=='1','Stock model refused: '..tostring(st.owner_detail));s.prepared=true
    local pointer=assert(tonumber(st.owner_pointer));local owner
    for _,o in ipairs(api.find('BP_PlayerPlane_PP0023_f14d_C')or{})do if o:IsValid()and o:GetAddress()==pointer then assert(not owner);owner=o end end
    assert(owner and owner:GetWorld():GetAddress()==context.world:GetAddress(),'Local owner actor missing')
    context.local_owner_actor=owner;context.local_owner_verified=true;owner:SetActorEnableCollision(false)
    owner:SetActorHiddenInGame(false);s.phase='local_model_ready';log('owner_lab_native_ready',st.owner_detail)
   end
  end
  if s.prepared then if not s.loaded then native.loaded();s.loaded=status('guest-pilot-status.tsv').state=='guest_world_loaded_sent'end;native.capture_input();local bytes=read('guest-owner-local.ac8p');if bytes then pose=view.owner(bytes).pose;s.phase='local_model_running'end end
  save();d.observe(c,{client=s})
 end
 function s.step()local ok,why=xpcall(step,debug.traceback);if not ok then s.error=tostring(why);c.error=s.error;log('owner_lab_error',s.error);s.stop(s.error);d.observe(c,{client=s})end end
 save();return s
end
function M.run(source,output,dll)
 local s=M.new(source,output,dll)
 RegisterKeyBind(Key.F9,function()ExecuteInGameThread(function()s.stop('user_f9')end)end)
 local function tick()s.step();if s.active then ExecuteInGameThreadWithDelay(16,tick)end end
 ExecuteInGameThreadWithDelay(1000,tick);return s
end
return M
