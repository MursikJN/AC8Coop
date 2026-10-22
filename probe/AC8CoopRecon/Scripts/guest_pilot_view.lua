-- Host authority for mission/health. R30 additionally decodes movement-only
-- owner snapshots; a verified local backend must supply the local camera pose.
local M={}
local function finite(x)return type(x)=='number'and x==x and math.abs(x)<1e12 end
function M.pose(p)
 if type(p)~='table'or type(p.position)~='table'or type(p.rotation)~='table'then return false end
 for i=1,3 do if not finite(p.position[i])or math.abs(p.position[i])>1e9 then return false end end
 local n=0;for i=1,4 do local x=p.rotation[i];if not finite(x)then return false end;n=n+x*x end
 return math.abs(n-1)<.002
end
function M.parse(data)
 assert(type(data)=='string'and(#data==368 or #data==392),'Invalid host state size')
 local magic,version,size,build,kind=string.unpack('<c4I2I2I4I4',data)
 assert(magic=='AC8P'and((version==1 or version==2)and size==368 or version==3 and size==392)and size==#data and build==25201480 and kind==1,'Invalid host state header')
 local sequence,generation,source_us,revision,mission,slot,aircraft,flags,count=string.unpack('<I8I8I8I4I4I4I4I4I4',data,41)
 assert(sequence>0 and generation>0 and revision>0 and mission==7 and slot==1 and aircraft==23 and count==4 and(flags&4)==4 and flags<= (version>=2 and 15 or 7),'Invalid host assignment')
 if version==3 then local x,y,z=string.unpack('<ddd',data,369);assert(x==0 and y==0 and z==0,'Host cannot write owner velocity')end
 local frame={sequence=sequence,generation=generation,source_us=source_us,revision=revision,flags=flags,poses={}}
 for i=0,3 do
  local role,model,x,y,z,qx,qy,qz,qw,speed,hp,maxhp,state=string.unpack('<I4I4dddfffffffI4',data,105+64*i)
  local p={role=role,aircraft=model,position={x,y,z},rotation={qx,qy,qz,qw},speed=speed,health=hp,max_health=maxhp,flags=state}
  assert(role==i and model>0 and model<=65535 and M.pose(p)and finite(speed)and speed>=0 and finite(hp)and finite(maxhp)and maxhp>0 and hp>=0 and hp<=maxhp,'Invalid replicated plane')
  frame.poses[i+1]=p
 end
 assert(frame.poses[2].aircraft==23,'Guest aircraft mismatch');return frame
end
function M.owner(data)
 assert(type(data)=='string'and #data==392,'Invalid owner state size')
 local magic,version,size,build,kind=string.unpack('<c4I2I2I4I4',data)
 assert(magic=='AC8P'and version==3 and size==392 and build==25201480 and kind==5,'Invalid owner state header')
 local sequence,generation,source_us,revision,mission,slot,aircraft,flags,count=string.unpack('<I8I8I8I4I4I4I4I4I4',data,41)
 assert(sequence>0 and generation>0 and source_us>0 and revision>0 and mission==7 and slot==1 and aircraft==23 and flags==0 and count==1,'Invalid owner assignment')
 -- No axes/reserved bytes, partner planes, damage, death or event writes.
 assert(data:sub(89,104)==string.rep('\0',16)and data:sub(169,368)==string.rep('\0',200),'Owner has non-movement payload')
 local role,model,x,y,z,qx,qy,qz,qw,speed,hp,maxhp,state=string.unpack('<I4I4dddfffffffI4',data,105)
 local pose={role=role,aircraft=model,position={x,y,z},rotation={qx,qy,qz,qw},speed=speed}
 assert(role==1 and model==23 and M.pose(pose)and finite(speed)and speed>=0 and speed<=1e6 and hp==0 and maxhp==0 and state==0,'Invalid owner plane')
 local vx,vy,vz=string.unpack('<ddd',data,369);local velocity={vx,vy,vz}
 for _,v in ipairs(velocity)do assert(finite(v)and math.abs(v)<=1e8,'Invalid owner velocity')end
 return {sequence=sequence,generation=generation,source_us=source_us,revision=revision,pose=pose,velocity=velocity}
end
function M.follow(p,back,up,ahead)
 assert(M.pose(p),'Invalid camera source pose');back=back or 4200;up=up or 1100;ahead=ahead or 6000
 local x,y,z,w=table.unpack(p.rotation)
 local forward={1-2*(y*y+z*z),2*(x*y+w*z),2*(x*z-w*y)}
 local at={X=p.position[1]-forward[1]*back,Y=p.position[2]-forward[2]*back,Z=p.position[3]-forward[3]*back+up}
 local target={X=p.position[1]+forward[1]*ahead,Y=p.position[2]+forward[2]*ahead,Z=p.position[3]+forward[3]*ahead}
 return at,target,forward
end
local function interpolate(a,b,t)
 local p={role=b.role,aircraft=b.aircraft,position={},rotation={},speed=b.speed,health=b.health,max_health=b.max_health,flags=b.flags}
 for i=1,3 do p.position[i]=a.position[i]+(b.position[i]-a.position[i])*t end
 local dot=0;for i=1,4 do dot=dot+a.rotation[i]*b.rotation[i]end
 local sign=dot<0 and-1 or 1;dot=math.min(1,math.abs(dot));local wa,wb=1-t,t
 if dot<.9995 then local theta=math.acos(dot);local denominator=math.sin(theta);wa=math.sin((1-t)*theta)/denominator;wb=math.sin(t*theta)/denominator end
 local n=0;for i=1,4 do local q=a.rotation[i]*wa+b.rotation[i]*sign*wb;p.rotation[i]=q;n=n+q*q end
 for i=1,4 do p.rotation[i]=p.rotation[i]/math.sqrt(n)end;return p
end
function M.stream()
 local s={}
 function s.accept(frame,received_ms)
  assert(finite(received_ms))
  if s.latest and(frame.generation<s.latest.frame.generation or(frame.generation==s.latest.frame.generation and frame.revision<s.latest.frame.revision))then return false end
  if s.latest and(frame.generation~=s.latest.frame.generation or frame.revision~=s.latest.frame.revision)then s.latest=nil;s.previous=nil end
  if s.latest and(frame.sequence<=s.latest.frame.sequence or received_ms<s.latest.time or frame.source_us<s.latest.frame.source_us)then return false end
  for _,p in ipairs(frame.poses)do if not M.pose(p)then return false end end
  s.previous=s.latest;s.latest={frame=frame,time=received_ms};return true
 end
 function s.sample(now_ms)
  if not s.latest or now_ms<s.latest.time or now_ms-s.latest.time>300 then return nil,'stale_host_state'end
  local latest=s.latest.frame
  if not s.previous or s.latest.time<=s.previous.time then return latest end
  local t=math.max(0,math.min(1,(now_ms-75-s.previous.time)/(s.latest.time-s.previous.time)))
  local out={sequence=latest.sequence,generation=latest.generation,revision=latest.revision,flags=latest.flags,poses={}}
  for i=1,4 do out.poses[i]=interpolate(s.previous.frame.poses[i],latest.poses[i],t)end;return out
 end
 return s
end
return M
