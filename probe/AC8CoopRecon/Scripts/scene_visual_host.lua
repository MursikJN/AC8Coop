-- Serialized mesh/material paths and relative poses. Never transfers UObject
-- addresses, controllers, AI state, animation instances or native pointers.
local M={}
local function valid(o)return o and o:IsValid()end
local function path(o)return valid(o)and o:GetFullName():match('^[^ ]+ (.+)$')or''end
function M.new(source,api)
 api=api or{static=StaticFindObject}
 local transform=assert(loadfile(source..'/scene_transform.lua'))()
 local meshclass=api.static('/Script/Engine.MeshComponent');local mathlib=api.static('/Script/Engine.Default__KismetMathLibrary')
 local s={cache={}}
 function s.clear()s.cache={}end
 function s.collect(actor,e)
  assert(valid(actor)and valid(meshclass)and valid(mathlib),'Mesh exporter context unavailable')
  local key=actor:GetFullName()..':'..actor:GetAddress();local cached=s.cache[key]
  if not cached then
   local array=actor:K2_GetComponentsByClass(meshclass);local count=type(array)=='table'and #array or array:GetArrayNum();assert(count<=128,'Actor mesh budget exceeded')
   cached={};for i=1,count do local c=array[i];if type(array)=='table'then c=c:get()end;if valid(c)then cached[#cached+1]=c end end
   table.sort(cached,function(a,b)return a:GetFullName()<b:GetFullName()end);s.cache[key]=cached
  end
  local result={};if actor.bHidden then
   local renderer=_G.AC8SceneEngine;local hidden=renderer and renderer.originals and renderer.originals[e.id]
   if not hidden or hidden.hidden then return result end
  end
  for slot,c in ipairs(cached)do
   if valid(c)and c:GetOwner():GetAddress()==actor:GetAddress()and c.bVisible and not c.bHiddenInGame then
    local mesh,kind
    if c:IsA('/Script/Engine.SkeletalMeshComponent')then mesh=c:GetSkeletalMeshAsset();kind='skeletal'
    elseif c:IsA('/Script/Engine.StaticMeshComponent')then mesh=c.StaticMesh;kind='static'end
    if valid(mesh)then
     local p=c:K2_GetComponentLocation();local q=mathlib:Conv_RotatorToQuaternion(c:K2_GetComponentRotation());local scale=c:K2_GetComponentScale()
     local rp,rq=transform.relative(e,{p.X,p.Y,p.Z},{q.X,q.Y,q.Z,q.W})
     local materials={};local count=c:GetNumMaterials();assert(count<=32,'Mesh material budget exceeded')
     for i=0,count-1 do
      local m=c:GetMaterial(i)
      for _=1,8 do if not valid(m)or not m:IsA('/Script/Engine.MaterialInstanceDynamic')then break end;m=m.Parent end
      local material=path(m);if not(material:match('^/Game/')or material:match('^/Engine/'))then material=''end;materials[#materials+1]=material
     end
     result[#result+1]={entity=e.id,slot=slot,kind=kind,asset=path(mesh),position=rp,rotation=rq,scale={scale.X,scale.Y,scale.Z},materials=materials}
    end
   end
  end
  return result
 end
 return s
end
return M
