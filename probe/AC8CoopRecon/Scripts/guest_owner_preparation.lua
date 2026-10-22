-- R31: real stock model preparation in the isolated guest world. No menu
-- clicks, actor possession, source pawn, or cross-process pointer copying.
local M={}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
function M.request(c,client,rows,api)
 api=api or{static=StaticFindObject,load=LoadAsset,find=FindAllOf}
 local x=assert(client.context);assert(x.isolated_world_verified and not x.preview and not x.live_preview,'Isolated owner world required')
 assert(client.camera and client.camera.active and same(x.pc:GetViewTarget(),client.camera.camera),'Owner camera is not attached')
 local path='/Game/Blueprints/Vehicle/Player/Plane/PP0023_f14d/BP_PlayerPlane_PP0023_f14d.BP_PlayerPlane_PP0023_f14d_C'
 local cl=api.static(path);if not valid(cl)then api.load(path);cl=api.static(path)end
 assert(valid(cl)and cl:IsChildOf(api.static('/Script/Live.LivePlayerPlane')),'Stock F-14D class missing')
 local cdo=cl:GetCDO();assert(valid(cdo),'Stock F-14D CDO missing')
 local manager
 for _,o in ipairs(api.find('LiveActorManager')or{})do if valid(o)and same(o:GetWorld(),x.world)then assert(not manager,'Multiple actor managers');manager=o end end
 assert(valid(manager),'Guest LiveActorManager unavailable; refusing stock BeginPlay')
 local function add(key,o)assert(valid(o));rows[#rows+1]=key..'\t'..string.format('0x%x',o:GetAddress())end
 -- Expected native types only. The native gate independently reads the actual
 -- manager children, their identities, world/outer links and mapper init state.
 for _,pair in ipairs({{'actor_manager_class','LiveActorManager'},{'combat_zone_class','LiveCombatZone'},{'actor_mapper_class','LiveObjectMapper'}})do
  local expected=api.static('/Script/Live.'..pair[2]);assert(valid(expected),'owner_world_object_class_missing: '..pair[2]);add(pair[1],expected)
 end
 for _,pair in ipairs({{'world',x.world},{'controller',x.pc},{'default_pawn',x.pawn},{'owner_class',cl},{'owner_cdo',cdo},{'actor_manager',manager},{'camera',client.camera.camera}})do add(table.unpack(pair))end
 local clprop=cl;local hidden
 for _=1,20 do
  if not valid(clprop)then break end
  clprop:ForEachProperty(function(p)if p:GetFName():ToString()=='bHidden'then assert(p:GetClass():GetFName():ToString()=='BoolProperty'and p:GetOffset_Internal()==0x58);hidden=p:GetAddress();return true end end)
  if hidden then break end;clprop=clprop:GetSuperStruct()
 end
 assert(hidden,'Actor bHidden reflection unavailable');rows[#rows+1]='hidden_property\t'..string.format('0x%x',hidden)
 rows[#rows+1]='mod_count\t'..(c.snapshot.guest_mod_count or'0')
 for i=0,tonumber(c.snapshot.guest_mod_count or'0')-1 do rows[#rows+1]='mod'..i..'\t'..assert(c.snapshot['guest_mod'..i])end
 rows[#rows+1]='weapon1\t'..assert(c.snapshot.guest_weapon1);rows[#rows+1]='weapon2\t'..assert(c.snapshot.guest_weapon2)
end
function M.seed(frame,view,api)
 api=api or{static=StaticFindObject}
 local p=assert(frame.poses[2]);assert(view.pose(p)and p.role==1 and p.aircraft==23,'Missing initial Baxter pose')
 local q=p.rotation
 local rot=api.static('/Script/Engine.Default__KismetMathLibrary'):Quat_Rotator({X=q[1],Y=q[2],Z=q[3],W=q[4]})
 local _,_,forward=view.follow(p)
 local rows={'generation\t'..frame.generation,'revision\t'..frame.revision,'host_sequence\t'..frame.sequence}
 local angles={assert(rot.Pitch or rot.pitch),assert(rot.Yaw or rot.yaw),assert(rot.Roll or rot.roll)}
 for i=1,3 do
  rows[#rows+1]='position'..(i-1)..'\t'..string.format('%.17g',p.position[i])
  rows[#rows+1]='angle'..(i-1)..'\t'..string.format('%.17g',angles[i])
  rows[#rows+1]='forward'..(i-1)..'\t'..string.format('%.17g',forward[i])
 end
 return table.concat(rows,'\n')..'\n'
end
return M
