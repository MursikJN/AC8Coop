-- Follow existing manager-owned widget trees, not a global UserWidget inventory.
return function(output,stamp)
 local f=assert(io.open(output..'/menu-dialog-'..stamp..'.tsv','w'));local seen,classes={},{};local count=0
 local function valid(o)return o and o:IsValid()end
 local function row(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v):gsub('[\r\n\t]',' '):sub(1,1500)end;f:write(table.concat(t,'\t'),'\n');f:flush()end
 local function walk(o,depth)
  if not valid(o)or depth>24 or count>=400 then return end
  local name=o:GetFullName();if seen[name]then return end;seen[name]=true;count=count+1
  local c=o:GetClass();local cn=c:GetFullName();row('widget',name,cn,o.Visibility,string.format('0x%x',o:GetAddress()))
  if not classes[cn]then
   classes[cn]=true
   c:ForEachFunction(function(fn)
    row('function',cn,fn:GetFName():ToString())
    fn:ForEachProperty(function(p)row('parameter',cn,fn:GetFName():ToString(),p:GetFName():ToString(),p:GetClass():GetFName():ToString())end)
   end)
  end
  if o:IsA('/Script/UMG.TextBlock')then row('text',name,o:GetText():ToString())end
  if o:IsA('/Script/UMG.UserWidget')then walk(o.WidgetTree.RootWidget,depth+1)
  elseif o:IsA('/Script/UMG.PanelWidget')then for i=0,math.min(o:GetChildrenCount(),64)-1 do walk(o:GetChildAt(i),depth+1)end end
 end
 local ok,err=pcall(function()
  for _,query in ipairs({'LiveNUIDialogManager','LiveMenuCampaignFreeMissionDifficultyWidget'})do
   for _,o in ipairs(FindAllOf(query)or{})do if valid(o)then walk(o,0)end end
  end
 end)
 row('summary',ok,err or'',count);f:close()
end
