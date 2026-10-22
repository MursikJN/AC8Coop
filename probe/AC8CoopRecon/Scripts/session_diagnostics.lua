-- Passive recorder: no UObject calls, network sends or changes to session state.
local M={}
local function clean(value)
 local s=tostring(value)
 if not utf8.len(s)then s=s:gsub('[\128-\255]','?')end
 if #s>2048 then s=s:sub(1,2048);while not utf8.len(s)do s=s:sub(1,-2)end;s=s..' [truncated]'end
 return s
end
local function encode(v,depth,budget)
 depth=depth or 0;budget=budget or{left=4096};budget.left=budget.left-1
 if budget.left<0 then return'"[budget]"'end
 local t=type(v)
 if t=='nil'then return'null'end
 if t=='boolean'then return v and'true'or'false'end
 if t=='number'then return v==v and math.abs(v)<math.huge and string.format('%.17g',v)or'null'end
 if t=='string'then return'"'..clean(v):gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',c:byte())end)..'"'end
 if t~='table'or depth>=7 then return'"[bounded]"'end
 local keys={};for k in pairs(v)do if type(k)=='string'and #keys<64 then keys[#keys+1]=k end end;table.sort(keys)
 local out={};for _,k in ipairs(keys)do out[#out+1]=encode(k,depth+1,budget)..':'..encode(v[k],depth+1,budget)end
 return'{'..table.concat(out,',')..'}'
end
M.encode=encode
local fields={'connected','have_snapshot','transport','reason','protocol','epoch','revision','generation','phase','scene','scene_return','scene_exit','ready_mask','loaded_mask','vote_mask','commit_mask','release_at','cinema_prepared','cinema_finished','cinema_state','cinema_commit_mask','cinema_at','stop_reason','restart_id','restart_ack','host_aircraft','guest_aircraft','guest_weapon1','guest_weapon2','clock_ready','request_ack','request_confirmed','reject'}
local files={'shared-session-status.tsv','shared-session-control.tsv','lobby-connection-status.txt','steam-invite-status.tsv','guest-pilot-status.tsv','client-world-status.tsv','cinema-playback-status.tsv','mission-pause-status.tsv','session-lifecycle.tsv','scene-host-status.tsv','plane-flight-status.tsv','guest-role-runtime-r19.tsv','guest-story-status-r19c.tsv'}
local context_keys={'epoch','revision','generation','phase','scene','self','peer','clock_ready','attempt_id','protocol'}
function M.new(output,meta,options)
 options=options or{};meta=meta or{};local now=options.now or os.time
 local d={sequence=0,slot=1,bytes=0,health_slot=1,health_bytes=0,rotations=0,health_rotations=0,errors=0,suppressed=0,last={},counts={},meta=meta,files={}}
 local max_bytes=options.max_bytes or 4*1024*1024;local slots=options.slots or 4
 local function save(name,data)
  local f=io.open(output..'/'..name,'wb');if not f then d.errors=d.errors+1;return false end
  local ok=f:write(data);local closed=f:close();if not ok or not closed then d.errors=d.errors+1;return false end;return true
 end
 function d.context(c)d.controller=c end
 function d.event(event,detail)
  local ok,why=pcall(function()
   local c=d.controller or{};local s=c.snapshot or{}
   local row={format='ac8-diagnostic-event-v1',sequence=d.sequence+1,utc=os.date('!%Y-%m-%dT%H:%M:%SZ'),unix=now(),session_id=meta.session_id or'unknown',package=meta.package or'unknown',role=c.role or meta.role or'unknown',event=clean(event),detail=detail or{}}
   row.context={config_token=c.token,local_tick_ms=s.local_tick,host_tick_ms=s.host_tick,clock_rtt_ms=s.clock_rtt}
   for _,k in ipairs(context_keys)do row.context[k]=s[k]end
   local line=encode(row)..'\n'
   if #line>65536 then row.detail={truncated=true,encoded_bytes=#line};line=encode(row)..'\n';d.truncated=(d.truncated or 0)+1 end
   local health=event=='health_sample';local slot=health and'health_slot'or'slot';local size=health and'health_bytes'or'bytes';local prefix=health and'diagnostics-health-'or'diagnostics-'
   if d[size]+#line>max_bytes then d[slot]=d[slot]%slots+1;d[size]=0;if health then d.health_rotations=d.health_rotations+1 else d.rotations=d.rotations+1 end;assert(save(string.format(prefix..'%02d.jsonl',d[slot]),''))end
   local f=assert(io.open(output..'/'..string.format(prefix..'%02d.jsonl',d[slot]),'ab'))
   local written=f:write(line);local closed=f:close();assert(written and closed,'diagnostic write failed')
   d.sequence=d.sequence+1;d[size]=d[size]+#line;d.counts[event]=(d.counts[event]or 0)+1
  end)
  if not ok then d.errors=d.errors+1;d.last_error=clean(why)end
  return ok
 end
 function d.changed(key,value,event)
  local fingerprint=encode(value);if d.last[key]==fingerprint then return false end
  d.last[key]=fingerprint;d.event(event or key,value);return true
 end
 function d.log(event,detail)
  -- Repeated identical failures are bounded; changed failures are retained.
  local key=clean(event)..'|'..clean(detail or'');local at=now()
  if key==d.last_log and at-(d.last_log_at or 0)<2 then d.suppressed=d.suppressed+1;return false end
  d.last_log=key;d.last_log_at=at;d.event('component_event',{name=event,message=clean(detail or'')});return true
 end
 local function read(name)
  local f=io.open(output..'/'..name,'rb');if not f then return nil,'missing'end
  local text=f:read(16385);f:close();if #text>16384 then return nil,'oversized'end
  local result={};local count=0
  for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)\r?\n')do count=count+1;if count>96 then return nil,'too_many_fields'end;result[k]=clean(v)end
  if not next(result)and name=='lobby-connection-status.txt'then
   result.transport=clean(text:match('^([^|\r\n]+)')or'')
   for k,v in text:gmatch('([%w_]+)=([^|\r\n]*)')do result[k]=clean(v:match('^%s*(.-)%s*$'))end
  end
  return result,next(result)and nil or'empty_or_partial'
 end
 function d.observe(c,components)
  d.context(c);local s=c.snapshot or{};local state={active=c.active,closing=c.closing,error=c.error,local_failure=c.local_failure,info=c.info}
  for _,k in ipairs(fields)do state[k]=s[k]end
  d.changed('session',state,'session_state')
  local tick=tonumber(s.local_tick);local at=now()
  -- The native timestamps are sampled worker clocks, not this event's exact time.
  if d.sample_at and at>=d.sample_at and at-d.sample_at<1 and(not tick or not d.sample_tick or tick-d.sample_tick<1000)then return end;d.sample_at=at;d.sample_tick=tick
  if tick and d.last_observed_tick and tick-d.last_observed_tick>2000 then d.event('observation_gap',{native_tick_delta_ms=tick-d.last_observed_tick,note='Gap between samples; may be GT scheduling, worker/file stall or a suspended process, not an FPS measurement'})end
  d.last_observed_tick=tick
  local parts={};for name,part in pairs(components or{})do
   if part then
    local value={component=name};for _,k in ipairs({'active','ready','phase','error','reason','loaded','held','quiesced','halted','quitting','sequence','generation','visual_error','isolated_world_verified'})do if type(part[k])~='table'and type(part[k])~='userdata'and type(part[k])~='function'then value[k]=part[k]end end
    if type(part.diagnostics)=='function'then local ok,result=pcall(part.diagnostics);if ok then value.metrics=result else value.diagnostic_error=clean(result)end end
    parts[name]=value;local stable={};for k,v in pairs(value)do if k~='metrics'and k~='sequence'then stable[k]=v end end;d.changed('part_'..name,stable,'component_state')
   end
  end
  local recorded={}
  for _,name in ipairs(files)do
   local result,why=read(name);local prior=d.files[name]
   if result then
    recorded[name]=result
    -- Every sample retains counters; file histories therefore survive overwrites.
    if(why or'present')~=prior then d.event('status_availability',{file=name,status=why or'present'})end
   elseif prior~=why then d.event('status_availability',{file=name,status=why})end
   d.files[name]=why or'present'
  end
  d.event('health_sample',{clock={local_tick_ms=tick,host_tick_ms=s.host_tick,clock_ready=s.clock_ready,clock_rtt_ms=s.clock_rtt,status_age_s=c.last_status and at-c.last_status},components=parts,status=recorded,pending=c.pending and {request=c.pending.request,age_s=at-c.pending.since}})
  save('diagnostics-summary.json',encode({format='ac8-diagnostic-summary-v1',meta=meta,sequence=d.sequence,rotations=d.rotations,health_rotations=d.health_rotations,truncated=d.truncated,write_errors=d.errors,last_error=d.last_error,suppressed=d.suppressed,counts=d.counts,last_state=state,last_local_tick_ms=tick,updated_unix=at})..'\n')
 end
 save('diagnostics-start.json',encode({format='ac8-diagnostic-start-v1',meta=meta,started_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'),max_file_bytes=max_bytes,event_file_slots=slots,health_file_slots=slots,timestamp_note='native ticks sampled at worker status publication; host ticks comparable only with clock_ready=1; UTC clocks may differ'})..'\n')
 d.event('diagnostics_started',meta)
 return d
end
return M
