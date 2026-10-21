-- Same replica lifecycle for the diagnostic viewer and a future UE renderer.
-- Adapter callbacks render data; they never run an independent campaign.
local M={}
function M.new(codec,adapter)
 local s={generation=0,revision=0,sequence=0,event_cursor=0,entities={},active=false,needs_baseline=true,events_applied=0}
 local function clear(reason)
  for id in pairs(s.entities)do adapter.remove(id,reason)end;s.entities={};s.previous=nil;s.current=nil;s.active=false
 end
 function s.reset(reason)clear(reason);s.generation=0;s.revision=0;s.sequence=0;s.event_cursor=0;s.needs_baseline=true end
 function s.accept(data,now,baseline)
  local f=codec.decode(data)
  if f.generation<s.generation or(f.generation==s.generation and(f.revision<s.revision or f.sequence<=s.sequence))then return false,'stale_frame'end
  if not f.complete then return false,'incomplete_inventory'end
  local fresh=f.generation~=s.generation
  if not fresh and s.current and f.source_ms<s.current.source_ms then return false,'host_clock_regressed'end
  local cursor=fresh and 0 or s.event_cursor
  if not fresh and f.event_cursor<cursor then return false,'event_cursor_regressed'end
  local first=f.events[1]and f.events[1].id or f.event_cursor+1
  if not fresh and not baseline and f.event_cursor>cursor and first>cursor+1 then s.needs_baseline=true;return false,'event_gap'end
  -- Validate the entire frame and event range before touching the render adapter.
  local expected=first;for _,e in ipairs(f.events)do assert(e.id==expected,'Noncontiguous events');expected=expected+1 end
  if adapter.prepare then adapter.prepare(f)end
  if fresh then clear('world_generation_changed');s.event_cursor=first-1;s.sequence=0;s.revision=0 end
  if baseline then s.event_cursor=math.max(s.event_cursor,first-1)end
  local next_entities={};for _,e in ipairs(f.entities)do next_entities[e.id]=e end
  for id,old in pairs(s.entities)do local e=next_entities[id];if not e or e.asset~=old.asset or e.kind~=old.kind then adapter.remove(id,e and'asset_changed'or'authoritative_despawn')end end
  for _,e in ipairs(f.entities)do local old=s.entities[e.id];if not old or old.asset~=e.asset or old.kind~=e.kind then adapter.create(e)end end
  for _,e in ipairs(f.events)do if e.id>s.event_cursor then
   adapter.event({id=e.id,kind=e.kind,entity=e.entity,detail=e.detail,generation=f.generation});s.event_cursor=e.id;s.events_applied=s.events_applied+1
  end end
  s.event_cursor=math.max(s.event_cursor,f.event_cursor)
  s.previous=s.current;s.previous_received=s.received;s.current=f;s.received=now;s.entities=next_entities
  s.generation=f.generation;s.revision=f.revision;s.sequence=f.sequence;s.active=true;s.needs_baseline=false
  if adapter.commit then adapter.commit(f)end
  adapter.menu(f.session);return true
 end
 function s.render(now)
  if not s.active or now<s.received or now-s.received>500 then s.active=false;return false,'stale_host'end
  local previous={};if s.previous then for _,e in ipairs(s.previous.entities)do previous[e.id]=e end end
  local t=1;if s.previous_received and s.received>s.previous_received then t=math.max(0,math.min(1,(now-100-s.previous_received)/(s.received-s.previous_received)))end
  for _,e in ipairs(s.current.entities)do
   local p={};for k,v in pairs(e)do p[k]=v end;local a=previous[e.id]
   if a and a.asset==e.asset then
    p.position={};for i=1,3 do p.position[i]=a.position[i]+(e.position[i]-a.position[i])*t end
    local dot=0;for i=1,4 do dot=dot+a.rotation[i]*e.rotation[i]end;local sign=dot<0 and-1 or 1;dot=math.min(1,math.abs(dot));local wa,wb=1-t,t
    if dot<.9995 then local theta=math.acos(dot);wa=math.sin((1-t)*theta)/math.sin(theta);wb=math.sin(t*theta)/math.sin(theta)end
    p.rotation={};local norm=0;for i=1,4 do local q=a.rotation[i]*wa+e.rotation[i]*sign*wb;p.rotation[i]=q;norm=norm+q*q end;for i=1,4 do p.rotation[i]=p.rotation[i]/math.sqrt(norm)end
   end
   adapter.update(p)
  end;return true
 end
 function s.view()
  if not s.current then return {screen='waiting_host',can_select_mission=false,can_start=false,can_ready=false,can_loadout=false,can_vote=false}end
  local stage=s.current.session.stage;local screens={[0]='lobby',[1]='loading_intro',[2]='cutscene',[3]='loading_hangar',[4]='hangar',[5]='loading_flight',[6]='flight',[7]='result',[8]='stopped'}
  return {screen=screens[stage],observed=s.current.session.observed,can_select_mission=false,can_start=false,can_ready=s.active and(stage==0 or stage==4),can_loadout=s.active and(stage==0 or stage==4),can_vote=s.active and stage==2,skip_votes=s.current.session.votes,paused=s.current.paused}
 end
 return s
end
return M
