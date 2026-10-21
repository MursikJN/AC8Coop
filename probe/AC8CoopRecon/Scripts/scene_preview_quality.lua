-- Scoped runtime rendering overrides for a paused one-PC preview. No config
-- files or user presets are saved. The exact original values are restored.
local M={}
function M.push(world,pc,library)
 library=library or StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 assert(library and library:IsValid(),'Preview console library unavailable')
 local s={values={},active=true}
 function s.restore()
  if not s.active then return end;s.active=false
  for _,v in ipairs(s.values)do library:ExecuteConsoleCommand(world,v.name..' '..v.value,pc)end
 end
 local ok,err=pcall(function()
  for _,name in ipairs({'r.DepthOfFieldQuality','r.MotionBlurQuality'})do
   local value=library:GetConsoleVariableIntValue(name);assert(type(value)=='number'and value%1==0,'Invalid preview quality value')
   s.values[#s.values+1]={name=name,value=value};library:ExecuteConsoleCommand(world,name..' 0',pc)
   assert(library:GetConsoleVariableIntValue(name)==0,'Preview quality override refused')
  end
 end)
 if not ok then s.restore();error(err)end;return s
end
return M
