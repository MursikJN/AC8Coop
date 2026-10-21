-- AC8W development wire. Data only: never load()/execute received source.
local M={MAX_BYTES=2097152,MAX_ENTITIES=2048,MAX_EVENTS=256,MAX_VISUALS=2048}
local function integer(x,min,max)return type(x)=='number'and x%1==0 and x>=min and x<=max end
local function finite(x)return type(x)=='number'and x==x and math.abs(x)<1e12 end
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
local function unhex(s,max_bytes)
 assert(#s<=2*(max_bytes or 2048)and #s%2==0 and not s:find('[^0-9a-f]'),'Invalid encoded text')
 return(s:gsub('..',function(c)return string.char(tonumber(c,16))end))
end
local function text(s,max)return type(s)=='string'and #s<=max and not s:find('[%z\1-\8\11\12\14-\31]')end
local kinds={plane=true,ground=true,ship=true,weapon=true,object=true}
local events={spawn=true,despawn=true,health=true,death=true,scene=true,pause=true,configuration=true,objective=true,result=true}
function M.validate(f)
 assert(type(f)=='table'and integer(f.sequence,1,2^53-1)and integer(f.generation,1,2^31-1)and integer(f.revision,1,2^31-1),'Invalid frame identity')
 assert(integer(f.source_ms,0,2^53-1)and text(f.world,2048)and type(f.complete)=='boolean'and type(f.paused)=='boolean','Invalid scene')
 local s=assert(f.session);for _,k in ipairs({'epoch','stage','mission','difficulty','ready','loaded','votes','scene','host_aircraft','guest_aircraft'})do assert(integer(s[k],0,65535),'Invalid session '..k)end
 assert(s.stage<=8 and s.ready<=3 and s.loaded<=3 and s.votes<=3 and text(s.observed,128),'Invalid menu state')
 assert(type(f.entities)=='table'and #f.entities<=M.MAX_ENTITIES and type(f.events)=='table'and #f.events<=M.MAX_EVENTS,'Scene budget exceeded')
 local seen={};for _,e in ipairs(f.entities)do
  assert(integer(e.id,1,2^31-1)and not seen[e.id]and kinds[e.kind]and integer(e.role,0,4)and type(e.alive)=='boolean','Invalid entity')
  seen[e.id]=true;assert(text(e.asset,2048)and text(e.label,512)and(e.health==false or finite(e.health)and e.health>=0),'Invalid entity metadata')
  assert(type(e.position)=='table'and #e.position==3 and type(e.rotation)=='table'and #e.rotation==4,'Invalid pose shape')
  local norm=0;for _,x in ipairs(e.position)do assert(finite(x)and math.abs(x)<=1e9,'Invalid position')end
  for _,x in ipairs(e.rotation)do assert(finite(x),'Invalid quaternion');norm=norm+x*x end;assert(math.abs(norm-1)<.003,'Invalid orientation')
 end
 if f.visuals~=nil then
  assert(type(f.visuals)=='table'and #f.visuals<=M.MAX_VISUALS and type(f.visual_complete)=='boolean','Invalid visual catalog')
  local slots={};for _,v in ipairs(f.visuals)do
   assert(seen[v.entity]and integer(v.slot,1,128)and(v.kind=='skeletal'or v.kind=='static'),'Invalid visual owner')
   local key=v.entity..':'..v.slot;assert(not slots[key],'Duplicate visual slot');slots[key]=true
   assert(text(v.asset,2048)and(v.asset:match('^/Game/')or v.asset:match('^/Engine/')),'Invalid mesh asset')
   assert(type(v.position)=='table'and #v.position==3 and type(v.rotation)=='table'and #v.rotation==4 and type(v.scale)=='table'and #v.scale==3,'Invalid visual transform')
   local n=0;for _,x in ipairs(v.position)do assert(finite(x)and math.abs(x)<1e8,'Invalid visual location')end
   for _,x in ipairs(v.rotation)do assert(finite(x),'Invalid visual rotation');n=n+x*x end;assert(math.abs(n-1)<.003,'Invalid visual quaternion')
   for _,x in ipairs(v.scale)do assert(finite(x)and math.abs(x)<=1e4,'Invalid mesh scale')end
   assert(type(v.materials)=='table'and #v.materials<=32,'Material budget exceeded')
   for _,m in ipairs(v.materials)do assert(text(m,2048)and(m==''or m:match('^/Game/')or m:match('^/Engine/'))and not m:find('[\r\n]'),'Invalid material path')end
  end
 end
 local previous=0;for _,e in ipairs(f.events)do
  assert(integer(e.id,1,2^53-1)and e.id>previous and events[e.kind]and integer(e.entity,0,2^31-1)and text(e.detail,2048),'Invalid event')
  previous=e.id
 end
 assert(integer(f.event_cursor,0,2^53-1)and(previous==0 or previous==f.event_cursor),'Invalid event cursor')
 return f
end
function M.encode(f)
 M.validate(f);local lines={};local function row(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v)end;lines[#lines+1]=table.concat(t,'\t')end
 row('AC8W',f.visuals and 2 or 1,25201480);row('frame',f.sequence,f.generation,f.revision,f.source_ms,f.complete and 1 or 0,f.paused and 1 or 0,f.event_cursor,hex(f.world))
 if f.visuals then lines[#lines]=lines[#lines]..'\t'..(f.visual_complete and'1'or'0')end
 local s=f.session;row('session',s.epoch,s.stage,s.mission,s.difficulty,s.ready,s.loaded,s.votes,s.scene,s.host_aircraft,s.guest_aircraft,hex(s.observed))
 for _,e in ipairs(f.entities)do row('entity',e.id,e.kind,e.role,e.alive and 1 or 0,e.health==false and'-'or string.format('%.17g',e.health),hex(e.asset),hex(e.label),table.unpack(e.position));lines[#lines]=lines[#lines]..string.format('\t%.17g\t%.17g\t%.17g\t%.17g',table.unpack(e.rotation))end
 for _,v in ipairs(f.visuals or{})do
  row('visual',v.entity,v.slot,v.kind,hex(v.asset));local t={}
  for _,a in ipairs({v.position,v.rotation,v.scale})do for _,x in ipairs(a)do t[#t+1]=string.format('%.17g',x)end end
  lines[#lines]=lines[#lines]..'\t'..table.concat(t,'\t')..'\t'..#v.materials..'\t'..hex(table.concat(v.materials,'\n'))
 end
 for _,e in ipairs(f.events)do row('event',e.id,e.kind,e.entity,hex(e.detail))end
 row('end',f.sequence,#f.entities,#f.events);if f.visuals then lines[#lines]=lines[#lines]..'\t'..#f.visuals end
 local data=table.concat(lines,'\n')..'\n';assert(#data<=M.MAX_BYTES,'Wire budget exceeded');return data
end
function M.decode(data)
 assert(type(data)=='string'and #data<=M.MAX_BYTES and data:sub(-1)=='\n'and not data:find('\r'),'Invalid wire length')
 local lines={};for line in data:gmatch('([^\n]*)\n')do
  assert(#line<=140000 and #lines<M.MAX_ENTITIES+M.MAX_EVENTS+M.MAX_VISUALS+5,'Row budget exceeded');local cols={};for value in(line..'\t'):gmatch('([^\t]*)\t')do cols[#cols+1]=value end;lines[#lines+1]=cols
 end
 local function n(s)assert(type(s)=='string'and s:match('^[%d.eE+%-]+$'),'Invalid number');local x=tonumber(s);assert(finite(x),'Invalid finite number');return x end
 local h=lines[1];assert(h and #h==3 and h[1]=='AC8W'and(h[2]=='1'or h[2]=='2')and h[3]=='25201480','Invalid wire version');local version=n(h[2])
 local r=assert(lines[2]);assert(#r==(version==2 and 10 or 9)and r[1]=='frame'and(r[6]=='0'or r[6]=='1')and(r[7]=='0'or r[7]=='1'),'Invalid frame row')
 local f={sequence=n(r[2]),generation=n(r[3]),revision=n(r[4]),source_ms=n(r[5]),complete=r[6]=='1',paused=r[7]=='1',event_cursor=n(r[8]),world=unhex(r[9]),session={},entities={},events={}}
 if version==2 then assert(r[10]=='0'or r[10]=='1');f.visuals={};f.visual_complete=r[10]=='1'end
 r=assert(lines[3]);assert(#r==12 and r[1]=='session','Invalid session row');for i,k in ipairs({'epoch','stage','mission','difficulty','ready','loaded','votes','scene','host_aircraft','guest_aircraft'})do f.session[k]=n(r[i+1])end;f.session.observed=unhex(r[12])
 local endrow=assert(lines[#lines]);assert(#endrow==(version==2 and 5 or 4)and endrow[1]=='end'and n(endrow[2])==f.sequence,'Incomplete frame')
 local in_events,in_visuals=false,false;for i=4,#lines-1 do r=lines[i]
  if r[1]=='entity'then
   assert(not in_events and not in_visuals and #r==15 and(r[5]=='0'or r[5]=='1'),'Invalid entity row')
   local health=false;if r[6]~='-'then health=n(r[6])end
   f.entities[#f.entities+1]={id=n(r[2]),kind=r[3],role=n(r[4]),alive=r[5]=='1',health=health,asset=unhex(r[7]),label=unhex(r[8]),position={n(r[9]),n(r[10]),n(r[11])},rotation={n(r[12]),n(r[13]),n(r[14]),n(r[15])}}
  elseif r[1]=='visual'then
   assert(version==2 and not in_events and #r==17,'Invalid visual row');in_visuals=true
   local materials={};local count=n(r[16]);assert(integer(count,0,32),'Invalid material count');local material_text=unhex(r[17],65568)
   if count>0 then for m in(material_text..'\n'):gmatch('([^\n]*)\n')do materials[#materials+1]=m end else assert(material_text=='')end;assert(#materials==count,'Truncated material list')
   f.visuals[#f.visuals+1]={entity=n(r[2]),slot=n(r[3]),kind=r[4],asset=unhex(r[5]),position={n(r[6]),n(r[7]),n(r[8])},rotation={n(r[9]),n(r[10]),n(r[11]),n(r[12])},scale={n(r[13]),n(r[14]),n(r[15])},materials=materials}
  else assert(r[1]=='event'and #r==5,'Invalid event row');in_events=true;f.events[#f.events+1]={id=n(r[2]),kind=r[3],entity=n(r[4]),detail=unhex(r[5])}end
 end
 assert(n(endrow[3])==#f.entities and n(endrow[4])==#f.events and(version==1 or n(endrow[5])==#f.visuals),'Truncated entity/event list');return M.validate(f)
end
return M
